"""Estimate per-AIP daily Bedrock spend and block profiles that exceed their daily limit.

Runs on a schedule. Each run:
  1. Reads today's (UTC) token metrics for every configured application inference profile.
  2. Converts tokens to an estimated USD cost with the configured per-million-token prices.
  3. Publishes EstimatedDailyCostUSD (and CostLimitBlocked) custom metrics, which drive the alert alarms.
  4. Reconciles a customer-managed IAM deny policy so exactly the over-limit profiles are denied.

The block is stateless: it is recomputed from today's usage on every run, so profiles unblock
automatically after the UTC day rolls over or after the limit is raised.
"""

import json
import os
from datetime import datetime, timezone

TOKEN_METRICS = {
    "InputTokenCount": "input_per_million",
    "OutputTokenCount": "output_per_million",
    "CacheReadInputTokenCount": "cache_read_per_million",
    "CacheWriteInputTokenCount": "cache_write_per_million",
}

BLOCK_SID = "DenyBlockedInferenceProfiles"
BLOCK_ROUTED_SID = "DenyRoutedFoundationModelsForBlockedProfiles"
MAX_POLICY_VERSIONS = 5
INVOKE_ACTIONS = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]


def load_config(path=None):
    path = path or os.path.join(os.path.dirname(__file__), "config.json")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def estimate_cost_usd(token_totals, pricing):
    """token_totals: metric name -> summed token count. pricing: price per million tokens."""
    return sum(token_totals.get(metric, 0.0) * pricing.get(key, 0.0) / 1_000_000 for metric, key in TOKEN_METRICS.items())


def blocked_profiles(profiles, costs):
    """Return the profiles whose estimated cost today has reached their daily limit."""
    return [p for p in profiles if p.get("daily_cost_limit_usd") is not None and costs[p["profile_id"]] >= p["daily_cost_limit_usd"]]


def placeholder_arn(config):
    return f"arn:{config['partition']}:bedrock:{config['region']}:{config['account_id']}:application-inference-profile/none-blocked"


def build_block_policy(config, blocked_arns):
    """Deny document for the given profile ARNs; a harmless placeholder keeps the policy valid when none are blocked."""
    arns = sorted(blocked_arns)
    if not arns:
        return {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "NoProfilesBlocked",
                    "Effect": "Deny",
                    "Action": INVOKE_ACTIONS,
                    "Resource": [placeholder_arn(config)],
                }
            ],
        }
    return {
        "Version": "2012-10-17",
        "Statement": [
            {"Sid": BLOCK_SID, "Effect": "Deny", "Action": INVOKE_ACTIONS, "Resource": arns},
            {
                "Sid": BLOCK_ROUTED_SID,
                "Effect": "Deny",
                "Action": INVOKE_ACTIONS,
                "Resource": [f"arn:{config['partition']}:bedrock:*::foundation-model/*"],
                "Condition": {"ArnEquals": {"bedrock:InferenceProfileArn": arns}},
            },
        ],
    }


def currently_blocked_arns(document):
    statements = document.get("Statement", [])
    if isinstance(statements, dict):
        statements = [statements]
    for statement in statements:
        if statement.get("Sid") == BLOCK_SID:
            resources = statement.get("Resource", [])
            return set([resources] if isinstance(resources, str) else resources)
    return set()


def day_start_utc(now):
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def fetch_token_totals(cloudwatch, profiles, start, end):
    """Sum each token metric per profile ID from the start of the UTC day."""
    queries, index = [], {}
    for p_index, profile in enumerate(profiles):
        for m_index, metric in enumerate(TOKEN_METRICS):
            query_id = f"p{p_index}m{m_index}"
            index[query_id] = (profile["profile_id"], metric)
            queries.append(
                {
                    "Id": query_id,
                    "MetricStat": {
                        "Metric": {
                            "Namespace": "AWS/Bedrock",
                            "MetricName": metric,
                            "Dimensions": [{"Name": "ModelId", "Value": profile["profile_id"]}],
                        },
                        # Hourly buckets keep the datapoint count small and make alignment irrelevant: we sum them all.
                        "Period": 3600,
                        "Stat": "Sum",
                    },
                    "ReturnData": True,
                }
            )

    totals = {p["profile_id"]: {} for p in profiles}
    for offset in range(0, len(queries), 500):
        kwargs = {"MetricDataQueries": queries[offset : offset + 500], "StartTime": start, "EndTime": end}
        while True:
            response = cloudwatch.get_metric_data(**kwargs)
            for result in response["MetricDataResults"]:
                profile_id, metric = index[result["Id"]]
                totals[profile_id][metric] = totals[profile_id].get(metric, 0.0) + sum(result["Values"])
            if not response.get("NextToken"):
                break
            kwargs["NextToken"] = response["NextToken"]
    return totals


def publish_metrics(cloudwatch, config, profiles, costs, blocked_ids):
    data = []
    for profile in profiles:
        dimensions = [{"Name": "ModelId", "Value": profile["profile_id"]}]
        data.append({"MetricName": "EstimatedDailyCostUSD", "Dimensions": dimensions, "Value": costs[profile["profile_id"]], "Unit": "None"})
        if profile.get("daily_cost_limit_usd") is not None:
            data.append(
                {
                    "MetricName": "CostLimitBlocked",
                    "Dimensions": dimensions,
                    "Value": 1.0 if profile["profile_id"] in blocked_ids else 0.0,
                    "Unit": "None",
                }
            )
    for offset in range(0, len(data), 1000):
        cloudwatch.put_metric_data(Namespace=config["metric_namespace"], MetricData=data[offset : offset + 1000])


def reconcile_policy(iam, config, desired_arns):
    """Make the managed deny policy match desired_arns. Returns True when a new version was written."""
    policy_arn = config["policy_arn"]
    default_version = iam.get_policy(PolicyArn=policy_arn)["Policy"]["DefaultVersionId"]
    document = iam.get_policy_version(PolicyArn=policy_arn, VersionId=default_version)["PolicyVersion"]["Document"]
    if currently_blocked_arns(document) == set(desired_arns):
        return False

    versions = iam.list_policy_versions(PolicyArn=policy_arn)["Versions"]
    if len(versions) >= MAX_POLICY_VERSIONS:
        oldest = min((v for v in versions if not v["IsDefaultVersion"]), key=lambda v: v["CreateDate"])
        iam.delete_policy_version(PolicyArn=policy_arn, VersionId=oldest["VersionId"])
    iam.create_policy_version(
        PolicyArn=policy_arn,
        PolicyDocument=json.dumps(build_block_policy(config, desired_arns)),
        SetAsDefault=True,
    )
    return True


def evaluate(config, cloudwatch, iam, now):
    profiles = config["profiles"]
    totals = fetch_token_totals(cloudwatch, profiles, day_start_utc(now), now)
    costs = {p["profile_id"]: estimate_cost_usd(totals[p["profile_id"]], p["pricing"]) for p in profiles}
    over_limit = blocked_profiles(profiles, costs)
    blocked_ids = {p["profile_id"] for p in over_limit}

    publish_metrics(cloudwatch, config, profiles, costs, blocked_ids)

    changed = False
    if config.get("policy_arn"):
        desired = {p["profile_arn"] for p in over_limit} if config["enforce"] else set()
        changed = reconcile_policy(iam, config, desired)

    summary = {
        "day_utc": day_start_utc(now).strftime("%Y-%m-%d"),
        "enforce": config["enforce"],
        "policy_updated": changed,
        "profiles": {p["name"]: {"estimated_cost_usd": round(costs[p["profile_id"]], 6), "over_limit": p["profile_id"] in blocked_ids} for p in profiles},
    }
    print(json.dumps(summary))
    return summary


def handler(event, context):
    import boto3  # Imported here so the pure functions above can be unit tested without boto3.

    config = load_config()
    return evaluate(config, boto3.client("cloudwatch"), boto3.client("iam"), datetime.now(timezone.utc))

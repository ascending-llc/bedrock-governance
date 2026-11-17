import json
import unittest
from datetime import datetime, timezone

import cost_limit_enforcer as enforcer

CONFIG = {"partition": "aws", "region": "us-east-1", "account_id": "123456789012", "policy_arn": "arn:aws:iam::123456789012:policy/p", "enforce": True}
PRICING = {"input_per_million": 3.0, "output_per_million": 15.0, "cache_read_per_million": 0.3, "cache_write_per_million": 3.75}
ARN_A = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/aaa"
ARN_B = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/bbb"


class FakeIam:
    def __init__(self, document, version_count=1):
        self.document = document
        self.versions = [{"VersionId": f"v{i}", "IsDefaultVersion": i == version_count, "CreateDate": i} for i in range(1, version_count + 1)]
        self.created = []
        self.deleted = []

    def get_policy(self, PolicyArn):
        return {"Policy": {"DefaultVersionId": "v1"}}

    def get_policy_version(self, PolicyArn, VersionId):
        return {"PolicyVersion": {"Document": self.document}}

    def list_policy_versions(self, PolicyArn):
        return {"Versions": self.versions}

    def delete_policy_version(self, PolicyArn, VersionId):
        self.deleted.append(VersionId)

    def create_policy_version(self, **kwargs):
        self.created.append(kwargs)


class FakeCloudWatch:
    def __init__(self, values, pages=1):
        self.values = values  # (profile_id, metric) -> list of hourly sums
        self.pages = pages
        self.published = []
        self.calls = []

    def get_metric_data(self, **kwargs):
        self.calls.append(kwargs)
        if "NextToken" not in kwargs and self.pages > 1:
            results = self._results(kwargs, first_half=True)
            return {"MetricDataResults": results, "NextToken": "more"}
        return {"MetricDataResults": self._results(kwargs, first_half=False)}

    def _results(self, kwargs, first_half):
        results = []
        for query in kwargs["MetricDataQueries"]:
            stat = query["MetricStat"]
            key = (stat["Metric"]["Dimensions"][0]["Value"], stat["Metric"]["MetricName"])
            values = self.values.get(key, [])
            if self.pages > 1:
                mid = len(values) // 2
                values = values[:mid] if first_half else values[mid:]
            results.append({"Id": query["Id"], "Values": values})
        return results

    def put_metric_data(self, **kwargs):
        self.published.append(kwargs)


class CostEstimateTests(unittest.TestCase):
    def test_cost_prices_every_token_type_per_million(self):
        totals = {"InputTokenCount": 2_000_000, "OutputTokenCount": 1_000_000, "CacheReadInputTokenCount": 1_000_000, "CacheWriteInputTokenCount": 1_000_000}
        self.assertAlmostEqual(enforcer.estimate_cost_usd(totals, PRICING), 6.0 + 15.0 + 0.3 + 3.75)

    def test_unpriced_cache_tokens_cost_nothing(self):
        pricing = {"input_per_million": 1.0, "output_per_million": 2.0}
        self.assertAlmostEqual(enforcer.estimate_cost_usd({"CacheReadInputTokenCount": 10**9}, pricing), 0.0)

    def test_limit_is_inclusive_and_profiles_without_limit_are_never_blocked(self):
        profiles = [
            {"profile_id": "a", "daily_cost_limit_usd": 50.0},
            {"profile_id": "b", "daily_cost_limit_usd": 50.0},
            {"profile_id": "c", "daily_cost_limit_usd": None},
        ]
        over = enforcer.blocked_profiles(profiles, {"a": 50.0, "b": 49.99, "c": 10_000.0})
        self.assertEqual([p["profile_id"] for p in over], ["a"])


class PolicyTests(unittest.TestCase):
    def test_empty_policy_is_a_valid_placeholder_that_blocks_nothing_real(self):
        policy = enforcer.build_block_policy(CONFIG, [])
        self.assertEqual(len(policy["Statement"]), 1)
        self.assertEqual(enforcer.currently_blocked_arns(policy), set())

    def test_block_policy_denies_profile_and_routed_foundation_models(self):
        policy = enforcer.build_block_policy(CONFIG, [ARN_B, ARN_A])
        direct, routed = policy["Statement"]
        self.assertEqual(direct["Effect"], "Deny")
        self.assertEqual(direct["Resource"], [ARN_A, ARN_B])
        self.assertEqual(routed["Condition"]["ArnEquals"]["bedrock:InferenceProfileArn"], [ARN_A, ARN_B])
        self.assertEqual(enforcer.currently_blocked_arns(policy), {ARN_A, ARN_B})

    def test_reconcile_is_a_noop_when_already_in_sync(self):
        iam = FakeIam(enforcer.build_block_policy(CONFIG, [ARN_A]))
        self.assertFalse(enforcer.reconcile_policy(iam, CONFIG, {ARN_A}))
        self.assertEqual(iam.created, [])

    def test_reconcile_writes_new_default_version_and_unblocks(self):
        iam = FakeIam(enforcer.build_block_policy(CONFIG, [ARN_A]))
        self.assertTrue(enforcer.reconcile_policy(iam, CONFIG, set()))
        self.assertTrue(iam.created[0]["SetAsDefault"])
        self.assertEqual(enforcer.currently_blocked_arns(json.loads(iam.created[0]["PolicyDocument"])), set())

    def test_reconcile_deletes_oldest_non_default_version_at_the_limit(self):
        iam = FakeIam(enforcer.build_block_policy(CONFIG, []), version_count=5)
        iam.versions[0]["IsDefaultVersion"] = False
        iam.versions[4]["IsDefaultVersion"] = True
        enforcer.reconcile_policy(iam, CONFIG, {ARN_A})
        self.assertEqual(iam.deleted, ["v1"])


class EvaluateTests(unittest.TestCase):
    NOW = datetime(2026, 11, 16, 15, 30, tzinfo=timezone.utc)

    def config(self, enforce=True, limit=50.0):
        return {
            **CONFIG,
            "enforce": enforce,
            "metric_namespace": "BedrockGovernance",
            "profiles": [{"name": "sonnet", "profile_id": "aaa", "profile_arn": ARN_A, "pricing": PRICING, "daily_cost_limit_usd": limit}],
        }

    def test_over_limit_profile_is_blocked_and_metrics_published(self):
        # 4M output tokens * $15/M = $60 across two hourly buckets.
        cw = FakeCloudWatch({("aaa", "OutputTokenCount"): [1_000_000, 3_000_000]})
        iam = FakeIam(enforcer.build_block_policy(CONFIG, []))
        summary = enforcer.evaluate(self.config(), cw, iam, self.NOW)
        self.assertTrue(summary["profiles"]["sonnet"]["over_limit"])
        self.assertEqual(enforcer.currently_blocked_arns(json.loads(iam.created[0]["PolicyDocument"])), {ARN_A})
        names = {d["MetricName"]: d["Value"] for d in cw.published[0]["MetricData"]}
        self.assertAlmostEqual(names["EstimatedDailyCostUSD"], 60.0)
        self.assertEqual(names["CostLimitBlocked"], 1.0)

    def test_queries_start_at_utc_midnight(self):
        cw = FakeCloudWatch({})
        enforcer.evaluate(self.config(), cw, FakeIam(enforcer.build_block_policy(CONFIG, [])), self.NOW)
        self.assertEqual(cw.calls[0]["StartTime"], datetime(2026, 11, 16, tzinfo=timezone.utc))

    def test_monitor_mode_reports_but_never_blocks(self):
        cw = FakeCloudWatch({("aaa", "OutputTokenCount"): [4_000_000]})
        iam = FakeIam(enforcer.build_block_policy(CONFIG, []))
        summary = enforcer.evaluate(self.config(enforce=False), cw, iam, self.NOW)
        self.assertTrue(summary["profiles"]["sonnet"]["over_limit"])
        self.assertEqual(iam.created, [])

    def test_under_limit_releases_a_previous_block(self):
        cw = FakeCloudWatch({("aaa", "OutputTokenCount"): [100_000]})
        iam = FakeIam(enforcer.build_block_policy(CONFIG, [ARN_A]))
        summary = enforcer.evaluate(self.config(), cw, iam, self.NOW)
        self.assertFalse(summary["profiles"]["sonnet"]["over_limit"])
        self.assertEqual(enforcer.currently_blocked_arns(json.loads(iam.created[0]["PolicyDocument"])), set())

    def test_paginated_metric_data_is_summed(self):
        cw = FakeCloudWatch({("aaa", "OutputTokenCount"): [1_000_000, 3_000_000]}, pages=2)
        summary = enforcer.evaluate(self.config(), cw, FakeIam(enforcer.build_block_policy(CONFIG, [])), self.NOW)
        self.assertAlmostEqual(summary["profiles"]["sonnet"]["estimated_cost_usd"], 60.0)

    def test_profile_without_limit_publishes_cost_only(self):
        cfg = self.config(limit=None)
        cw = FakeCloudWatch({("aaa", "InputTokenCount"): [1_000_000]})
        enforcer.evaluate(cfg, cw, FakeIam(enforcer.build_block_policy(CONFIG, [])), self.NOW)
        self.assertEqual([d["MetricName"] for d in cw.published[0]["MetricData"]], ["EstimatedDailyCostUSD"])


if __name__ == "__main__":
    unittest.main()

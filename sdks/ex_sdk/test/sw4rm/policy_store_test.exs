defmodule Sw4rm.PolicyStoreTest do
  use ExUnit.Case, async: true

  alias Sw4rm.PolicyStore.{Policy, InMemory}

  setup do
    {:ok, store} = InMemory.start_link()
    %{store: store}
  end

  describe "set_policy/2" do
    test "stores a policy and returns its ID", %{store: store} do
      policy = Policy.new(name: "test-policy", rules: [:rule1])
      id = InMemory.set_policy(store, policy)
      assert is_binary(id)
    end
  end

  describe "get_policy/2" do
    test "retrieves stored policy", %{store: store} do
      policy = Policy.new(policy_id: "p1", name: "test")
      InMemory.set_policy(store, policy)
      retrieved = InMemory.get_policy(store, "p1")
      assert retrieved.name == "test"
    end

    test "returns nil for missing", %{store: store} do
      assert InMemory.get_policy(store, "nope") == nil
    end
  end

  describe "delete_policy/2" do
    test "deletes existing policy", %{store: store} do
      policy = Policy.new(policy_id: "p1", name: "test")
      InMemory.set_policy(store, policy)
      assert InMemory.delete_policy(store, "p1") == true
      assert InMemory.get_policy(store, "p1") == nil
    end

    test "returns false for missing", %{store: store} do
      assert InMemory.delete_policy(store, "nope") == false
    end
  end

  describe "list_policies/2" do
    test "returns all policies", %{store: store} do
      InMemory.set_policy(store, Policy.new(policy_id: "p1", name: "a"))
      InMemory.set_policy(store, Policy.new(policy_id: "p2", name: "b"))
      assert length(InMemory.list_policies(store)) == 2
    end

    test "filters by enabled_only", %{store: store} do
      InMemory.set_policy(store, Policy.new(policy_id: "p1", enabled: true))
      InMemory.set_policy(store, Policy.new(policy_id: "p2", enabled: false))
      result = InMemory.list_policies(store, enabled_only: true)
      assert length(result) == 1
    end
  end

  describe "clear/1" do
    test "removes all and returns count", %{store: store} do
      InMemory.set_policy(store, Policy.new(policy_id: "p1"))
      InMemory.set_policy(store, Policy.new(policy_id: "p2"))
      assert InMemory.clear(store) == 2
      assert InMemory.list_policies(store) == []
    end
  end

  describe "Policy.new/1" do
    test "generates policy_id if not provided" do
      policy = Policy.new(name: "test")
      assert is_binary(policy.policy_id)
      assert String.starts_with?(policy.policy_id, "policy-")
    end

    test "accepts all fields" do
      policy =
        Policy.new(
          policy_id: "custom-id",
          name: "my policy",
          description: "desc",
          rules: [:r1, :r2],
          enabled: false,
          metadata: %{key: "val"}
        )

      assert policy.policy_id == "custom-id"
      assert policy.name == "my policy"
      assert policy.enabled == false
      assert policy.rules == [:r1, :r2]
    end
  end
end

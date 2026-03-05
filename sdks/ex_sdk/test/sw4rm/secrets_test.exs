defmodule Sw4rm.SecretsTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Secrets.{EnvBackend, FileBackend, Resolver}

  describe "EnvBackend" do
    test "reads from environment with prefix" do
      System.put_env("SW4RM_SECRET_API_KEY", "secret123")
      backend = %EnvBackend{}
      assert EnvBackend.get_secret(backend, "api_key") == "secret123"
      System.delete_env("SW4RM_SECRET_API_KEY")
    end

    test "returns nil for missing" do
      backend = %EnvBackend{}
      assert EnvBackend.get_secret(backend, "nonexistent_key_xyz") == nil
    end

    test "set_secret returns read_only error" do
      backend = %EnvBackend{}
      assert EnvBackend.set_secret(backend, "k", "v") == {:error, :read_only}
    end

    test "delete_secret returns false" do
      assert EnvBackend.delete_secret(%EnvBackend{}, "k") == false
    end

    test "list_secrets returns empty" do
      assert EnvBackend.list_secrets(%EnvBackend{}) == []
    end
  end

  describe "FileBackend" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "sw4rm_test_secrets_#{:rand.uniform(1_000_000)}.json")
      on_exit(fn -> File.rm(tmp) end)
      {:ok, fb} = FileBackend.start_link(file_path: tmp)
      %{fb: fb, path: tmp}
    end

    test "set and get", %{fb: fb} do
      assert :ok = FileBackend.set_secret(fb, "key1", "val1")
      assert FileBackend.get_secret(fb, "key1") == "val1"
    end

    test "get returns nil for missing", %{fb: fb} do
      assert FileBackend.get_secret(fb, "nope") == nil
    end

    test "delete existing key", %{fb: fb} do
      FileBackend.set_secret(fb, "key1", "val1")
      assert FileBackend.delete_secret(fb, "key1") == true
      assert FileBackend.get_secret(fb, "key1") == nil
    end

    test "delete missing key returns false", %{fb: fb} do
      assert FileBackend.delete_secret(fb, "nope") == false
    end

    test "list_secrets returns keys", %{fb: fb} do
      FileBackend.set_secret(fb, "a", "1")
      FileBackend.set_secret(fb, "b", "2")
      keys = FileBackend.list_secrets(fb)
      assert Enum.sort(keys) == ["a", "b"]
    end

    test "persists to file", %{fb: fb, path: path} do
      FileBackend.set_secret(fb, "persist", "yes")
      assert File.exists?(path)
    end
  end

  describe "Resolver" do
    test "resolves from env backend" do
      System.put_env("SW4RM_SECRET_RESOLVER_TEST", "from_env")
      env = %EnvBackend{}
      resolver = Resolver.new([env])
      assert Resolver.resolve(resolver, "resolver_test") == "from_env"
      System.delete_env("SW4RM_SECRET_RESOLVER_TEST")
    end

    test "falls back to later backends" do
      env = %EnvBackend{prefix: "NONEXISTENT_PREFIX_"}

      tmp = Path.join(System.tmp_dir!(), "sw4rm_resolver_#{:rand.uniform(1_000_000)}.json")
      on_exit(fn -> File.rm(tmp) end)
      {:ok, fb} = FileBackend.start_link(file_path: tmp)
      FileBackend.set_secret(fb, "mykey", "from_file")

      resolver = Resolver.new([env, fb])
      assert Resolver.resolve(resolver, "mykey") == "from_file"
    end

    test "returns fallback when no backend has key" do
      resolver = Resolver.new([], fallback: "default_val")
      assert Resolver.resolve(resolver, "missing") == "default_val"
    end
  end
end

defmodule Sw4rm.PersistenceTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Persistence.{InMemory, JsonFile}

  describe "InMemory" do
    setup do
      {:ok, store} = InMemory.start_link()
      %{store: store}
    end

    test "save and load records", %{store: store} do
      records = [%{id: 1, data: "hello"}, %{id: 2, data: "world"}]
      assert {:ok, 2} = InMemory.save_records(store, records)
      assert {:ok, ^records} = InMemory.load_records(store)
    end

    test "load returns empty for missing namespace", %{store: store} do
      assert {:ok, []} = InMemory.load_records(store, namespace: "other")
    end

    test "clear_records removes data", %{store: store} do
      InMemory.save_records(store, [1, 2, 3])
      assert {:ok, 3} = InMemory.clear_records(store)
      assert {:ok, []} = InMemory.load_records(store)
    end

    test "namespaces are independent", %{store: store} do
      InMemory.save_records(store, [:a], namespace: "ns1")
      InMemory.save_records(store, [:b], namespace: "ns2")

      assert {:ok, [:a]} = InMemory.load_records(store, namespace: "ns1")
      assert {:ok, [:b]} = InMemory.load_records(store, namespace: "ns2")
    end

    test "list_namespaces", %{store: store} do
      InMemory.save_records(store, [:a], namespace: "alpha")
      InMemory.save_records(store, [:b], namespace: "beta")
      namespaces = InMemory.list_namespaces(store)
      assert Enum.sort(namespaces) == ["alpha", "beta"]
    end
  end

  describe "JsonFile" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "sw4rm_persist_#{:rand.uniform(1_000_000)}")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      {:ok, store} = JsonFile.start_link(base_directory: tmp_dir)
      %{store: store, dir: tmp_dir}
    end

    test "save and load records", %{store: store} do
      records = [%{"id" => 1}, %{"id" => 2}]
      assert {:ok, 2} = JsonFile.save_records(store, records)
      assert {:ok, loaded} = JsonFile.load_records(store)
      assert length(loaded) == 2
    end

    test "load returns empty for missing file", %{store: store} do
      assert {:ok, []} = JsonFile.load_records(store, namespace: "empty")
    end

    test "clear_records removes file", %{store: store} do
      JsonFile.save_records(store, [1, 2])
      assert {:ok, 2} = JsonFile.clear_records(store)
      assert {:ok, []} = JsonFile.load_records(store)
    end

    test "namespaces use separate files", %{store: store} do
      JsonFile.save_records(store, [1], namespace: "a")
      JsonFile.save_records(store, [2], namespace: "b")

      assert {:ok, [1]} = JsonFile.load_records(store, namespace: "a")
      assert {:ok, [2]} = JsonFile.load_records(store, namespace: "b")
    end

    test "list_namespaces", %{store: store} do
      JsonFile.save_records(store, [1], namespace: "ns1")
      JsonFile.save_records(store, [2], namespace: "ns2")
      namespaces = JsonFile.list_namespaces(store)
      assert Enum.sort(namespaces) == ["ns1", "ns2"]
    end
  end
end

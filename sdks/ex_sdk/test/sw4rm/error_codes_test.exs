defmodule Sw4rm.ErrorCodesTest do
  use ExUnit.Case, async: true

  alias Sw4rm.ErrorCodes

  describe "from_string/1" do
    test "known codes return correct integers" do
      assert ErrorCodes.from_string("BUFFER_FULL") == 1
      assert ErrorCodes.from_string("REDIRECT") == 20
      assert ErrorCodes.from_string("INTERNAL_ERROR") == 99
    end

    test "unknown code raises ArgumentError" do
      assert_raise ArgumentError, ~r/unknown error code/, fn ->
        ErrorCodes.from_string("DOES_NOT_EXIST")
      end
    end
  end
end

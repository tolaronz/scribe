defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  describe "apply_updates/3" do
    test "returns :no_updates for empty list" do
      user = user_fixture()
      credential = user_credential_fixture(%{user_id: user.id, provider: "salesforce"})

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", [])
    end

    test "filters updates with apply: false" do
      user = user_fixture()
      credential = user_credential_fixture(%{user_id: user.id, provider: "salesforce"})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", updates)
    end
  end
end

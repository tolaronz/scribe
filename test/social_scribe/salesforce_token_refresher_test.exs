defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  test "ensure_valid_token/1 returns credential when not near expiry" do
    user = user_fixture()

    credential =
      user_credential_fixture(%{
        user_id: user.id,
        provider: "salesforce",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    assert {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
    assert result.id == credential.id
  end
end

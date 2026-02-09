defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  import Mox

  alias SocialScribe.SalesforceSuggestions
  alias SocialScribe.AIContentGeneratorMock

  setup :verify_on_exit!

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        phone: nil,
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", email: "test@example.com"}

      assert SalesforceSuggestions.merge_with_contact(suggestions, contact) == []
    end
  end

  describe "generate_suggestions_from_meeting/1" do
    test "filters unsupported fields and sets defaults" do
      meeting = %{id: "meeting-1"}

      AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn ^meeting ->
        {:ok,
         [
           %{field: "email", value: "test@example.com", context: "ctx", timestamp: "00:01"},
           %{field: "unsupported_field", value: "ignore"}
         ]}
      end)

      assert {:ok, suggestions} = SalesforceSuggestions.generate_suggestions_from_meeting(meeting)
      assert length(suggestions) == 1

      suggestion = hd(suggestions)
      assert suggestion.field == "email"
      assert suggestion.current_value == nil
      assert suggestion.apply == true
      assert suggestion.has_change == true
    end
  end
end

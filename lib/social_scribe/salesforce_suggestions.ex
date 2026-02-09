defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates and formats Salesforce contact update suggestions by combining
  AI-extracted data with existing Salesforce contact information.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.SalesforceApi
  alias SocialScribe.Accounts.UserCredential

  @field_labels %{
    "firstname" => "First Name",
    "lastname" => "Last Name",
    "email" => "Email",
    "phone" => "Phone",
    "mobilephone" => "Mobile Phone",
    "jobtitle" => "Job Title",
    "address" => "Mailing Street",
    "city" => "Mailing City",
    "state" => "Mailing State",
    "zip" => "Mailing Postal Code",
    "country" => "Mailing Country"
  }

  @supported_fields Map.keys(@field_labels)

  @doc """
  Generates suggested updates for a Salesforce contact based on a meeting transcript.
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    with {:ok, contact} <- SalesforceApi.get_contact(credential, contact_id),
         {:ok, ai_suggestions} <- AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
      suggestions =
        ai_suggestions
        |> Enum.map(&normalize_ai_suggestion/1)
        |> Enum.filter(&(&1.field in @supported_fields))
        |> Enum.map(fn suggestion ->
          field = suggestion.field
          current_value = get_contact_field(contact, field)

          %{
            field: field,
            label: Map.get(@field_labels, field, field),
            current_value: current_value,
            new_value: suggestion.value,
            context: suggestion.context,
            timestamp: suggestion.timestamp,
            apply: true,
            has_change: current_value != suggestion.value
          }
        end)
        |> Enum.filter(& &1.has_change)

      {:ok, %{contact: contact, suggestions: suggestions}}
    end
  end

  @doc """
  Generates suggestions without fetching contact data.
  Useful when contact hasn't been selected yet.
  """
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(&normalize_ai_suggestion/1)
          |> Enum.filter(&(&1.field in @supported_fields))
          |> Enum.map(fn suggestion ->
            %{
              field: suggestion.field,
              label: Map.get(@field_labels, suggestion.field, suggestion.field),
              current_value: nil,
              new_value: suggestion.value,
              context: suggestion.context,
              timestamp: suggestion.timestamp,
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    suggestions
    |> Enum.map(fn suggestion ->
      current_value = get_contact_field(contact, suggestion.field)

      %{
        suggestion
        | current_value: current_value,
          has_change: current_value != suggestion.new_value,
          apply: true
      }
    end)
    |> Enum.filter(& &1.has_change)
  end

  defp normalize_ai_suggestion(%{field: field} = suggestion) do
    %{
      field: field,
      value: suggestion.value,
      context: Map.get(suggestion, :context),
      timestamp: Map.get(suggestion, :timestamp)
    }
  end

  defp normalize_ai_suggestion(%{"field" => field} = suggestion) do
    %{
      field: field,
      value: suggestion["value"],
      context: suggestion["context"],
      timestamp: suggestion["timestamp"]
    }
  end

  defp normalize_ai_suggestion(_), do: %{field: nil, value: nil, context: nil, timestamp: nil}

  defp get_contact_field(contact, field) when is_map(contact) do
    field_atom = String.to_existing_atom(field)
    Map.get(contact, field_atom)
  rescue
    ArgumentError -> nil
  end

  defp get_contact_field(_, _), do: nil
end

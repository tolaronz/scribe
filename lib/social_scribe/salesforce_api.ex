defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on auth errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @default_api_version "v59.0"

  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry",
    "Account.Name"
  ]

  @update_field_map %{
    "firstname" => "FirstName",
    "lastname" => "LastName",
    "email" => "Email",
    "phone" => "Phone",
    "mobilephone" => "MobilePhone",
    "jobtitle" => "Title",
    "address" => "MailingStreet",
    "city" => "MailingCity",
    "state" => "MailingState",
    "zip" => "MailingPostalCode",
    "country" => "MailingCountry"
  }

  defp api_version do
    Application.get_env(:social_scribe, :salesforce_api_version, @default_api_version)
  end

  defp base_url do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    config[:site] || System.get_env("SALESFORCE_SITE") || "https://login.salesforce.com"
  end

  defp client(access_token) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url()},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string.
  Returns up to 10 matching contacts with basic properties.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      case search_contacts_sosl(cred, query) do
        {:ok, contacts} when contacts != [] ->
          {:ok, contacts}

        {:ok, _} ->
          search_contacts_soql(cred, query)

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc """
  Gets a single contact by ID with selected properties.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      soql = build_contact_query(contact_id)

      case Tesla.get(client(cred.token), "/services/data/#{api_version()}/query", query: [q: soql]) do
        {:ok, %Tesla.Env{status: 200, body: %{"records" => [record | _]}}} ->
          {:ok, format_contact(record)}

        {:ok, %Tesla.Env{status: 200, body: %{"records" => []}}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Updates a contact's properties.
  `updates` should be a map of internal field names to new values.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      updates_map = map_updates(updates)

      if map_size(updates_map) == 0 do
        {:ok, :no_updates}
      else
        case Tesla.patch(
               client(cred.token),
               "/services/data/#{api_version()}/sobjects/contact/#{contact_id}",
               updates_map
             ) do
          {:ok, %Tesla.Env{status: status}} when status in [204, 200] ->
            {:ok, :updated}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  This is a convenience wrapper around update_contact/3.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  defp build_search_soql(query) do
    escaped = escape_soql(query)
    like = "%#{escaped}%"
    fields = Enum.join(@contact_fields, ", ")

    """
    SELECT #{fields}
    FROM Contact
    WHERE (
      FirstName LIKE '#{like}' OR
      LastName LIKE '#{like}' OR
      Name LIKE '#{like}' OR
      Email LIKE '#{like}' OR
      Phone LIKE '#{like}' OR
      MobilePhone LIKE '#{like}'
    )
    ORDER BY LastModifiedDate DESC
    LIMIT 10
    """
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp build_search_sosl(query) do
    escaped = escape_sosl(query)
    fields = Enum.join(@contact_fields, ", ")

    """
    FIND {#{escaped}*} IN ALL FIELDS
    RETURNING Contact(#{fields})
    LIMIT 10
    """
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp search_contacts_sosl(cred, query) do
    sosl = build_search_sosl(query)

    case Tesla.get(client(cred.token), "/services/data/#{api_version()}/search", query: [q: sosl]) do
      {:ok, %Tesla.Env{status: 200, body: %{"searchRecords" => records}}} when is_list(records) ->
        contacts =
          records
          |> Enum.filter(fn record ->
            get_in(record, ["attributes", "type"]) == "Contact" or Map.has_key?(record, "FirstName")
          end)
          |> Enum.map(&format_contact/1)

        {:ok, contacts}

      {:ok, %Tesla.Env{status: 200, body: records}} when is_list(records) ->
        contacts =
          records
          |> Enum.filter(fn record ->
            get_in(record, ["attributes", "type"]) == "Contact" or Map.has_key?(record, "FirstName")
          end)
          |> Enum.map(&format_contact/1)

        {:ok, contacts}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp search_contacts_soql(cred, query) do
    soql = build_search_soql(query)

    case Tesla.get(client(cred.token), "/services/data/#{api_version()}/query", query: [q: soql]) do
      {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
        contacts = Enum.map(records, &format_contact/1)
        {:ok, contacts}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp build_contact_query(contact_id) do
    escaped = escape_soql(contact_id)
    fields = Enum.join(@contact_fields, ", ")

    "SELECT #{fields} FROM Contact WHERE Id = '#{escaped}' LIMIT 1"
  end

  defp escape_soql(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end

  defp escape_sosl(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("{", "\\{")
    |> String.replace("}", "\\}")
  end

  defp map_updates(updates) when is_map(updates) do
    updates
    |> Enum.reduce(%{}, fn {field, value}, acc ->
      field_str = to_string(field)

      case @update_field_map[field_str] do
        nil -> acc
        salesforce_field -> Map.put(acc, salesforce_field, value)
      end
    end)
  end

  defp format_contact(%{"Id" => id} = record) do
    %{
      id: id,
      firstname: record["FirstName"],
      lastname: record["LastName"],
      email: record["Email"],
      phone: record["Phone"],
      mobilephone: record["MobilePhone"],
      jobtitle: record["Title"],
      address: record["MailingStreet"],
      city: record["MailingCity"],
      state: record["MailingState"],
      zip: record["MailingPostalCode"],
      country: record["MailingCountry"],
      company: get_in(record, ["Account", "Name"]),
      display_name: format_display_name(record)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(record) do
    firstname = record["FirstName"] || ""
    lastname = record["LastName"] || ""
    email = record["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    case SalesforceTokenRefresher.ensure_valid_token(credential) do
      {:ok, credential} ->
        case api_call.(credential) do
          {:error, {:api_error, status, body}} when status in [401, 403] ->
            if is_token_error?(body) do
              Logger.info("Salesforce token expired, refreshing and retrying...")
              retry_with_fresh_token(credential, api_call)
            else
              Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
              {:error, {:api_error, status, body}}
            end

          other ->
            other
        end

      {:error, reason} ->
        {:error, {:token_refresh_failed, reason}}
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(body) when is_list(body) do
    Enum.any?(body, fn
      %{"errorCode" => "INVALID_SESSION_ID"} -> true
      %{"message" => message} when is_binary(message) ->
        String.contains?(String.downcase(message), "session")

      _ ->
        false
    end)
  end

  defp is_token_error?(%{"error" => "invalid_grant"}), do: true
  defp is_token_error?(%{"errorCode" => "INVALID_SESSION_ID"}), do: true
  defp is_token_error?(%{"message" => message}) when is_binary(message) do
    String.contains?(String.downcase(message), "session")
  end

  defp is_token_error?(_), do: false
end

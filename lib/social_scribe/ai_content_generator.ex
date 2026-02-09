defmodule SocialScribe.AIContentGenerator do
  @moduledoc "Generates content using Google Gemini."

  @behaviour SocialScribe.AIContentGeneratorApi

  alias SocialScribe.Meetings
  alias SocialScribe.Automations

  @gemini_model "gemini-2.0-flash-lite"
  @gemini_api_base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl SocialScribe.AIContentGeneratorApi
  def generate_follow_up_email(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        Based on the following meeting transcript, please draft a concise and professional follow-up email.
        The email should summarize the key discussion points and clearly list any action items assigned, including who is responsible if mentioned.
        Keep the tone friendly and action-oriented.

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_automation(automation, meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        #{Automations.generate_prompt_for_automation(automation)}

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_hubspot_suggestions(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        You are an AI assistant that extracts contact information updates from meeting transcripts.

        Analyze the following meeting transcript and extract any information that could be used to update a CRM contact record.

        Look for mentions of:
        - Phone numbers (phone, mobilephone)
        - Email addresses (email)
        - Company name (company)
        - Job title/role (jobtitle)
        - Physical address details (address, city, state, zip, country)

        IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

        The transcript includes timestamps in [MM:SS] format at the start of each line.

        Return your response as a JSON array of objects. Each object should have:
        - "field": the CRM field name (use exactly: firstname, lastname, email, phone, mobilephone, company, jobtitle, address, city, state, zip, country)
        - "value": the extracted value
        - "context": a brief quote of where this was mentioned
        - "timestamp": the timestamp in MM:SS format where this was mentioned

        If no contact information updates are found, return an empty array: []

        Example response format:
        [
          {"field": "phone", "value": "555-123-4567", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
          {"field": "company", "value": "Acme Corp", "context": "Sarah said she just joined Acme Corp", "timestamp": "05:47"}
        ]

        ONLY return valid JSON, no other text.

        Meeting transcript:
        #{meeting_prompt}
        """

      case call_gemini(prompt) do
        {:ok, response} ->
          parse_hubspot_suggestions(response)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_contact_answer(meeting, contact, question) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        contact_info = format_contact_for_prompt(contact)

        prompt = """
        You are an AI assistant that answers questions about HubSpot and Salesforce contacts using their CRM data and meeting transcripts.

        Contact Information:
        #{contact_info}

        Meeting Transcript:
        #{meeting_prompt}

        User Question: #{question}

        Instructions:
        1. Answer the user's question using ONLY the information provided in the contact data and meeting transcript above.
        2. If the information needed to answer the question is not available, clearly state that the information is not available.
        3. Provide specific details and context from the sources when answering.
        4. Cite the source of your information (e.g., "According to HubSpot", "According to Salesforce", "In the meeting transcript", "Based on both sources").
        5. Keep your response concise but informative.
        6. Do not make up or infer information that is not explicitly stated in the provided sources.

        Answer the question directly and clearly.
        """

        call_gemini(prompt)

    end
  end

  defp format_contact_for_prompt(contact) do
    fields = [
      {"First Name", contact.firstname},
      {"Last Name", contact.lastname},
      {"Email", contact.email},
      {"Phone", contact.phone},
      {"Mobile Phone", contact.mobilephone},
      {"Company", contact.company},
      {"Job Title", contact.jobtitle},
      {"Address", contact.address},
      {"City", contact.city},
      {"State", contact.state},
      {"ZIP Code", contact.zip},
      {"Country", contact.country}
    ]

    fields
    |> Enum.filter(fn {_label, value} -> value != nil and value != "" end)
    |> Enum.map(fn {label, value} -> "- #{label}: #{value}" end)
    |> Enum.join("\n")
  end

  defp parse_hubspot_suggestions(response) do
    # Clean up the response - remove markdown code blocks if present
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\n?/, "")
      |> String.replace(~r/\n?```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, suggestions} when is_list(suggestions) ->
        formatted =
          suggestions
          |> Enum.filter(&is_map/1)
          |> Enum.map(fn s ->
            %{
              field: s["field"],
              value: s["value"],
              context: s["context"],
              timestamp: s["timestamp"]
            }
          end)
          |> Enum.filter(fn s -> s.field != nil and s.value != nil end)

        {:ok, formatted}

      {:ok, _} ->
        {:ok, []}

      {:error, _} ->
        # If JSON parsing fails, return empty suggestions
        {:ok, []}
    end
  end

  defp call_gemini(prompt_text) do
    api_key = Application.get_env(:social_scribe, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, {:config_error, "Gemini API key is missing - set GEMINI_API_KEY env var"}}
    else
      path = "/#{@gemini_model}:generateContent?key=#{api_key}"

      payload = %{
        contents: [
          %{
            parts: [%{text: prompt_text}]
          }
        ]
      }

      case Tesla.post(client(), path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          text_path = [
            "candidates",
            Access.at(0),
            "content",
            "parts",
            Access.at(0),
            "text"
          ]

          case get_in(body, text_path) do
            nil -> {:error, {:parsing_error, "No text content found in Gemini response", body}}
            text_content -> {:ok, text_content}
          end

        {:ok, %Tesla.Env{status: status, body: error_body}} ->
          {:error, {:api_error, status, error_body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @gemini_api_base_url},
      Tesla.Middleware.JSON
    ])
  end
end

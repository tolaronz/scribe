defmodule SocialScribeWeb.MeetingLive.ChatComponent do
  use SocialScribeWeb, :live_component

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApi

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex-shrink-0 p-6 pb-0">
        <h2 class="text-xl font-medium tracking-tight text-slate-900 mb-4">HubSpot Contact Chat</h2>
        <p class="text-base font-light leading-7 text-slate-500 mb-6">
          Ask questions about your contacts using their HubSpot data and meeting transcripts.
          Type @ to mention a contact.
        </p>
      </div>

      <div class="flex-1 overflow-y-auto px-6">
        <.message_history
          messages={@messages}
          contacts={@contacts}
          loading={@loading}
          searching={@searching}
          dropdown_open={@dropdown_open}
          query={@query}
          error={@error}
        />
      </div>

      <div class="flex-shrink-0 p-6 pt-4">
        <.message_input
          message={@message}
          contacts={@contacts}
          loading={@loading}
          searching={@searching}
          dropdown_open={@dropdown_open}
          query={@query}
          target={@myself}
          error={@error}
        />
      </div>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :contacts, :list, required: true
  attr :loading, :boolean, required: true
  attr :searching, :boolean, required: true
  attr :dropdown_open, :boolean, required: true
  attr :query, :string, required: true
  attr :error, :string, required: true

  defp message_history(assigns) do
    ~H"""
    <div class="bg-slate-50 rounded-lg p-4 mb-4">
      <%= if Enum.empty?(@messages) do %>
        <div class="text-center text-slate-500 py-8">
          <p class="mb-2">No messages yet. Start a conversation by typing a question!</p>
          <p class="text-sm">Example: "What's @John Doe's email address?"</p>
        </div>
      <% else %>
        <div :for={message <- @messages} class="mb-4">
          <div class={["flex", message.type == "user" && "justify-end"]}>
            <div class={["max-w-xs lg:max-w-md", message.type == "user" && "order-2"]}>
              <div class={["px-4 py-2 rounded-lg", message.type == "user" && "bg-indigo-500 text-white"] ++
                [message.type == "ai" && "bg-white border border-slate-200"]}>
                <div class="text-sm">
                  <%= if message.type == "user" do %>
                    <span class="font-medium">You</span>
                  <% else %>
                    <span class="font-medium text-slate-600">AI Assistant</span>
                  <% end %>
                </div>
                <div class="mt-1 text-sm">
                  <%= if message.type == "ai" and message.contact do %>
                    <div class="text-xs text-slate-500 mb-1">
                      Contact: <span class="font-medium">{message.contact.display_name}</span>
                    </div>
                  <% end %>

                  <%= if message.type == "user" and message.contact do %>
                    <!-- User message with highlighted contact -->
                    <%= for part <- parse_message_with_highlights(message.content, message.contact) do %>
                      <%= case part do %>
                        <% {:highlight, name} -> %>
                          <span class="inline-block p-0.5 rounded bg-indigo-700 mr-0 text-indigo-100 font-medium">
                            {name}
                          </span>
                        <% {:text, text} -> %>
                          {text}
                      <% end %>
                    <% end %>
                  <% else %>
                    <!-- Regular message without highlighting -->
                    {message.content}
                  <% end %>
                </div>
                <div class="mt-2 text-xs text-slate-400">
                  {message.timestamp}
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp message_input(assigns) do
    ~H"""
    <div class="relative">
      <form phx-submit="send_message" phx-target={@target}>
        <div :if={@dropdown_open and @contacts != []} class="absolute bottom-full left-0 right-0 mb-2 z-10 bg-white border border-slate-200 rounded-lg shadow-lg max-h-48 overflow-y-auto">
          <div class="p-2 text-xs text-slate-500 border-b">Select a contact</div>
          <ul>
            <li
              :for={contact <- @contacts}
              class="p-2 hover:bg-slate-50 cursor-pointer"
              phx-click="select_contact"
              phx-value-id={contact.id}
              phx-target={@target}
            >
              <div class="font-medium">{contact.display_name}</div>
              <div class="text-sm text-slate-500">{contact.email}</div>
            </li>
          </ul>
        </div>

        <div class="relative">
          <div
            id="chat-message-input"
            contenteditable="true"
            phx-hook="MentionInput"
            phx-update="ignore"
            class="w-full px-4 py-3 pr-12 border border-slate-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 resize-none overflow-y-auto"
            style="min-height: 80px; max-height: 200px;"
            data-placeholder="Type your question... (e.g., What's @John Doe's email?)"
          ></div>

          <!-- Hidden input to store the actual message text -->
          <input type="hidden" name="message" id="message-hidden-input" value={@message} />

          <button
            type="submit"
            disabled={@message == "" or @searching}
            class={["absolute right-2 bottom-2 p-2 rounded-lg",
              @message != "" and not @searching && "bg-indigo-500 hover:bg-indigo-600 text-white" ||
              "bg-slate-200 text-slate-400 cursor-not-allowed"]}
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
            </svg>
          </button>
        </div>

        <div :if={@error} class="mt-2 text-red-600 text-sm">{@error}</div>
      </form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:messages, fn -> [] end)
      |> assign_new(:message, fn -> "" end)
      |> assign_new(:contacts, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:dropdown_open, fn -> false end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:selected_contact_id, fn -> nil end)
      |> assign_new(:collapsed, fn -> false end)
      |> assign_new(:highlighted_contacts, fn -> [] end)

    {:ok, socket}
  end

  @impl true
  def handle_event("search_contacts", %{"message" => message}, socket) do
    # Extract mention from message
    mention_match = Regex.run(~r/@([a-zA-Z\s]+)$/, message)

    # Always update the message in the socket
    socket = assign(socket, message: message)

    if mention_match do
      query = String.trim(Enum.at(mention_match, 1))

      if String.length(query) >= 2 do
        # Search contacts directly
        case HubspotApi.search_contacts(socket.assigns.credential, query) do
          {:ok, contacts} ->
            {:noreply, assign(socket,
              contacts: contacts,
              searching: false,
              error: nil,
              query: query,
              dropdown_open: true
            )}

          {:error, reason} ->
            {:noreply, assign(socket,
              error: "Failed to search contacts: #{inspect(reason)}",
              searching: false,
              query: query,
              dropdown_open: false
            )}
        end
      else
        {:noreply, assign(socket, query: query, dropdown_open: query != "")}
      end
    else
      {:noreply, assign(socket, dropdown_open: false, query: "")}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

    if contact do
      # Extract first name from display name
      first_name = extract_first_name(contact.display_name)

      # Send data to JavaScript hook to update the input
      socket = push_event(socket, "update_contact_highlight", %{
        contact_id: contact.id,
        display_name: contact.display_name,
        first_name: "@" <> first_name
      })

      {:noreply, assign(socket, selected_contact_id: contact.id, dropdown_open: false, query: "")}
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, assign(socket, error: "Please enter a message")}
    else
      # Extract contact name - handle possessives and punctuation
      mention_match = Regex.run(~r/@([a-zA-Z\s]+?)(?:'s|\s|$)/, message)

      if mention_match do
        contact_name =
          mention_match
          |> Enum.at(1)
          |> String.trim()

        # Search for contact by name
        case HubspotApi.search_contacts(socket.assigns.credential, contact_name) do
          {:ok, contacts} ->
            if Enum.any?(contacts) do
              contact = Enum.at(contacts, 0)

              # Add user message to history WITH contact info
              user_message = %{
                type: "user",
                content: message,
                timestamp: format_timestamp(DateTime.utc_now()),
                contact: contact  # Store contact so we can highlight it
              }

              socket = assign(socket,
                messages: socket.assigns.messages ++ [user_message],
                message: "",
                error: nil,
                loading: true,
                dropdown_open: false,
                query: ""
              )
              |> push_event("clear_input", %{})

              # Generate AI response
              generate_and_add_ai_response(socket, contact, message)
            else
              {:noreply, assign(socket, error: "No contact found with name: #{contact_name}")}
            end

          {:error, reason} ->
            {:noreply, assign(socket, error: "Failed to search contacts: #{inspect(reason)}")}
        end
      else
        {:noreply, assign(socket, error: "Please mention a contact with @name")}
      end
    end
  end

  defp generate_and_add_ai_response(socket, contact, question) do
    # Get full contact data
    case HubspotApi.get_contact_with_properties(socket.assigns.credential, contact.id) do
      {:ok, full_contact} ->
        # Generate AI response
        case AIContentGeneratorApi.generate_contact_answer(socket.assigns.meeting, full_contact, question) do
          {:ok, response} ->
            ai_message = %{
              type: "ai",
              content: response,
              timestamp: format_timestamp(DateTime.utc_now()),
              contact: full_contact
            }

            {:noreply, assign(socket,
              messages: socket.assigns.messages ++ [ai_message],
              loading: false,
              message: ""
            )}

          {:error, reason} ->
            error_message = %{
              type: "ai",
              content: "I'm sorry, I couldn't generate a response: #{inspect(reason)}",
              timestamp: format_timestamp(DateTime.utc_now()),
              contact: nil
            }

            {:noreply, assign(socket,
              messages: socket.assigns.messages ++ [error_message],
              loading: false,
              message: ""
            )}
        end

      {:error, reason} ->
        error_message = %{
          type: "ai",
          content: "I'm sorry, I couldn't retrieve the contact information: #{inspect(reason)}",
          timestamp: format_timestamp(DateTime.utc_now()),
          contact: nil
        }

        {:noreply, assign(socket,
          messages: socket.assigns.messages ++ [error_message],
          loading: false,
          message: ""
        )}
    end
  end

  defp format_timestamp(datetime) do
    hour = datetime.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute = datetime.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{hour}:#{minute}"
  end

  defp parse_message_with_highlights(message_content, contact) do
    first_name = extract_first_name(contact.display_name)

    # Split by first name and create highlight parts
    parts = Regex.split(~r/(@#{Regex.escape(first_name)})/, message_content, include_captures: true)

    Enum.map(parts, fn part ->
      part = String.trim_leading(part)

      if part == "@" <> first_name do
        {:highlight, part}
      else
        {:text, part}
      end
    end)
  end

  defp extract_first_name(display_name) do
    # Extract first name from full name (everything before the first space)
    case String.split(display_name, " ") do
      [first_name | _] -> first_name
      [] -> display_name
    end
  end
end

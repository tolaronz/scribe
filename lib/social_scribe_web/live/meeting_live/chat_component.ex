defmodule SocialScribeWeb.MeetingLive.ChatComponent do
  use SocialScribeWeb, :live_component

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApi
  alias SocialScribe.SalesforceApi


  @source_order ~w(hubspot salesforce facebook linkedin google)
  @source_keywords %{
    "hubspot" => ["hubspot"],
    "salesforce" => ["salesforce"],
    "facebook" => ["facebook"],
    "linkedin" => ["linkedin"],
    "google" => ["google", "google meet", "gmail", "calendar"]
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col bg-white">
      <div class="flex-shrink-0 px-6 pt-6">
        <div class="mt-4 flex items-center justify-between">
          <div class="flex items-center gap-[2px] m-[-18px_0px_-8px_-8px] text-[20px]">
            <button
              type="button"
              phx-click="toggle_tab"
              phx-value-tab="chat"
              phx-target={@myself}
              class={[
                "rounded-full px-3 py-1 text-[20px] transition-colors",
                @active_tab == "chat" && "bg-slate-100 text-slate-800 shadow-sm" ||
                  "text-slate-400 hover:text-slate-600"
              ]}
            >
              Chat
            </button>
            <button
              type="button"
              phx-click="toggle_tab"
              phx-value-tab="history"
              phx-target={@myself}
              class={[
                "rounded-full px-3 py-1 text-[20px] transition-colors",
                @active_tab == "history" && "bg-slate-100 text-slate-800 shadow-sm" ||
                  "text-slate-400 hover:text-slate-600"
              ]}
            >
              History
            </button>
          </div>
          <button
            type="button"
            phx-click="new_chat"
            phx-target={@myself}
            class="text-slate-400 hover:text-slate-600"
            title="New chat"
          >
            <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" aria-hidden="true">
              <path d="M10 4v12M4 10h12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
          </button>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto px-6 pt-4">
        <%= if @active_tab == "history" do %>
          <.history_view
            chat_sessions={@chat_sessions}
            selected_session_id={@selected_session_id}
            history_messages={@history_messages}
            available_sources={@available_sources}
            target={@myself}
          />
        <% else %>
          <.message_history messages={@messages} available_sources={@available_sources} />
        <% end %>
      </div>

      <%= if @active_tab == "chat" do %>
        <div class="flex-shrink-0 px-6 pb-6 pt-2">
          <.message_input
            message={@message}
            contacts={@contacts}
            loading={@loading}
            searching={@searching}
            dropdown_open={@dropdown_open}
            query={@query}
            available_sources={@available_sources}
            target={@myself}
            error={@error}
          />
        </div>
      <% end %>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :available_sources, :list, required: true

  defp message_history(assigns) do
    ~H"""
    <div class="flex flex-col gap-6 pb-10">
      <div class="flex items-center gap-3 text-[15px] font-medium text-slate-400">
        <div class="h-px flex-1 bg-slate-200"></div>
        <span>{format_timestamp(DateTime.utc_now())} – {format_date(Date.utc_today())}</span>
        <div class="h-px flex-1 bg-slate-200"></div>
      </div>

      <div class="text-[20px] leading-8 text-slate-700">
        I can answer questions about Jump meetings and data – just ask!
      </div>

      <%= if Enum.empty?(@messages) do %>
      <% else %>
        <div :for={message <- @messages} class="space-y-2">
          <%= if message.type == "user" do %>
            <div class="flex justify-end">
              <div class="max-w-[78%] rounded-2xl bg-slate-100 px-4 py-3 text-[22px] leading-8 text-slate-700 shadow-sm">
                <%= if message.contact do %>
                  <%= for part <- parse_message_with_highlights(message.content, message.contact) do %>
                    <%= case part do %>
                      <% {:highlight, name} -> %>
                        <span class="inline-flex items-center gap-1 rounded-full bg-slate-200 px-2 py-0.5 text-slate-700">
                          <span class="flex h-4 w-4 items-center justify-center rounded-full bg-slate-500 text-[10px] text-white">
                            {mention_initial(name)}
                          </span>
                          <span>{mention_label(name)}</span>
                        </span>
                      <% {:text, text} -> %>
                        {text}
                    <% end %>
                  <% end %>
                <% else %>
                  {message.content}
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="flex items-start gap-2">
              <span class="mt-1 h-5 w-5 rounded-full bg-slate-200"></span>
              <div class="max-w-[80%] text-[22px] leading-8 text-slate-700">
                {message.content}
                <.sources_row sources={sources_for_message(message, @available_sources)} />
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :chat_sessions, :list, required: true
  attr :selected_session_id, :any, required: true
  attr :history_messages, :list, required: true
  attr :available_sources, :list, required: true
  attr :target, :any, required: true

  defp history_view(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 pb-6">
      <div>
        <div class="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-2">History</div>
        <div class="flex flex-col gap-2">
          <%= if Enum.empty?(@chat_sessions) do %>
            <div class="text-[22px] leading-8 text-slate-400">No history yet.</div>
          <% else %>
            <button
              :for={session <- @chat_sessions}
              type="button"
              phx-click="select_history_session"
              phx-value-id={session.id}
              phx-target={@target}
              class={[
                "w-full flex items-center rounded-lg border px-3 py-2 text-[22px] leading-8 transition-colors",
                session.id == @selected_session_id &&
                  "border-slate-900 bg-slate-100 text-slate-900" ||
                  "border-slate-200 bg-white text-slate-600 hover:border-slate-300"
              ]}
            >
              <div class="flex flex-col items-start gap-1 text-left">
                <span class="text-[15px] text-slate-400">{format_session_date(session.started_at)}</span>
                <span class="text-[22px] leading-8 text-slate-700 truncate w-full">
                  {session.preview || "New chat"}
                </span>
              </div>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :sources, :list, required: true
  attr :variant, :string, default: "default"

  defp sources_row(assigns) do
    ~H"""
    <div class="mt-3 flex items-center gap-2 text-xs text-slate-400">
      <span>Sources</span>
      <.source_icons sources={@sources} variant={@variant} />
    </div>
    """
  end

  attr :sources, :list, required: true
  attr :variant, :string, default: "default"

  defp source_icons(assigns) do
    ~H"""
    <%= if @variant == "input" do %>
      <span class="inline-flex items-center">
        <%= for {source, index} <- Enum.with_index(@sources) do %>
          <span class={[
            "inline-flex h-6 w-6 items-center justify-center rounded-full border border-slate-200 bg-white",
            index > 0 && "-ml-[8px]"
          ]}>
            <.source_icon source={source} />
          </span>
        <% end %>
      </span>
    <% else %>
      <span class="inline-flex items-center gap-2">
        <%= for source <- @sources do %>
          <.source_icon source={source} />
        <% end %>
      </span>
    <% end %>
    """
  end

  attr :source, :string, required: true

  defp source_icon(assigns) do
    ~H"""
    <%= case @source do %>
      <% "google" -> %>
        <span
          class="inline-flex h-4 w-4 flex-none items-center justify-center text-[11px] font-semibold leading-none"
          title="Google"
          aria-label="Google"
          style="background: conic-gradient(#4285F4 0 90deg, #34A853 90deg 180deg, #FBBC05 180deg 270deg, #EA4335 270deg 360deg); -webkit-background-clip: text; background-clip: text; color: transparent;"
        >
          G
        </span>
      <% "linkedin" -> %>
        <span
          class="inline-flex h-4 w-4 flex-none items-center justify-center rounded-[3px] bg-[#0a66c2] text-[9px] font-bold leading-none text-white"
          title="LinkedIn"
          aria-label="LinkedIn"
        >
          in
        </span>
      <% "facebook" -> %>
        <span
          class="inline-flex h-4 w-4 flex-none items-center justify-center rounded-full bg-[#1877f2] text-[10px] font-bold leading-none text-white"
          title="Facebook"
          aria-label="Facebook"
        >
          f
        </span>
      <% "hubspot" -> %>
        <span
          class="inline-flex h-4 w-4 flex-none items-center justify-center rounded-full bg-[#ff7a59] text-[10px] font-bold leading-none text-white"
          title="HubSpot"
          aria-label="HubSpot"
        >
          h
        </span>
      <% "salesforce" -> %>
        <span
          class="inline-flex h-4 w-4 flex-none items-center justify-center rounded-full bg-[#00a1e0] text-[10px] font-bold leading-none text-white"
          title="Salesforce"
          aria-label="Salesforce"
        >
          s
        </span>
      <% _ -> %>
        <span
          class="inline-flex h-4 w-4 flex-none items-center justify-center rounded-full bg-slate-400 text-[9px] font-semibold leading-none text-white"
          title={source_label(@source)}
          aria-label={source_label(@source)}
        >
          {source_initial(@source)}
        </span>
    <% end %>
    """
  end

  attr :available_sources, :list, required: true

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
              phx-value-id={get_contact_field(contact, :id)}
              phx-target={@target}
            >
              <div class="flex items-center justify-between">
                <div>
                  <div class="font-medium">{get_contact_field(contact, :display_name)}</div>
                  <div class="text-sm text-slate-500">{get_contact_field(contact, :email)}</div>
                </div>
                <div class="flex items-center space-x-2">
                  <%= case get_contact_field(contact, :source) do %>
                    <% "HubSpot" -> %>
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                        HubSpot
                      </span>
                    <% "Salesforce" -> %>
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
                        Salesforce
                      </span>
                    <% _ -> %>
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                        Unknown
                      </span>
                  <% end %>
                </div>
              </div>
            </li>
          </ul>
        </div>

        <div class="rounded-2xl border border-blue-400/70 bg-white px-3 pb-3 pt-3 shadow-sm">
          <div class="flex items-center">
            <span class="inline-flex items-center gap-1 rounded-full border border-slate-200 bg-slate-50 px-2 py-1 text-xs text-slate-500">
              <span class="font-semibold text-slate-600">@</span>
              Add context
            </span>
          </div>

          <div
            id="chat-message-input"
            contenteditable="true"
            phx-hook="MentionInput"
            phx-update="ignore"
            class="mt-2 min-h-[86px] w-full text-[22px] leading-8 text-slate-700 placeholder:text-slate-400"
            style="max-height: 200px;"
            data-placeholder="Ask anything about your meetings"
          ></div>

          <input type="hidden" name="message" id="message-hidden-input" value={@message} />

          <div class="mt-3 flex items-center justify-between">
            <.sources_row sources={@available_sources} variant="input" />
            <button
              type="submit"
              disabled={@message == "" or @searching}
              class={[
                "flex h-9 w-9 items-center justify-center rounded-full border",
                @message != "" and not @searching &&
                  "border-slate-800 bg-slate-800 text-white" ||
                  "border-slate-200 bg-slate-100 text-slate-400 cursor-not-allowed"
              ]}
            >
              <svg class="h-4 w-4" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <path d="M10 4l5 5M10 4l-5 5M10 4v9" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            </button>
          </div>
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
      |> assign_new(:message, fn -> "" end)
      |> assign_new(:contacts, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:dropdown_open, fn -> false end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:selected_contact_id, fn -> nil end)
      |> assign_new(:collapsed, fn -> false end)
      |> assign_new(:active_tab, fn -> "chat" end)
      |> assign_new(:selected_session_id, fn -> nil end)

    available_sources = load_available_sources(socket.assigns[:current_user])
    socket = assign_new(socket, :available_sources, fn -> available_sources end)

    {socket, chat_session} = ensure_active_session(socket)

    messages = load_messages_for_session(chat_session)
    chat_sessions = load_chat_sessions(socket.assigns.meeting, socket.assigns.current_user)

    selected_session_id =
      normalize_selected_session_id(socket.assigns.selected_session_id, chat_sessions)

    history_messages =
      if selected_session_id do
        load_messages_for_session_id(selected_session_id, chat_sessions)
      else
        []
      end

    socket =
      assign(socket,
        messages: messages,
        chat_sessions: chat_sessions,
        selected_session_id: selected_session_id,
        history_messages: history_messages
      )

    # Scroll to bottom when component mounts or messages are loaded
    socket =
      if socket.assigns.active_tab == "chat" do
        push_event(socket, "scroll_to_bottom", %{})
      else
        socket
      end

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
        # Search contacts from both HubSpot and Salesforce
        hubspot_task = Task.async(fn ->
          case socket.assigns.hubspot_credential do
            nil -> {:ok, []}
            credential -> HubspotApi.search_contacts(credential, query)
          end
        end)

        salesforce_task = Task.async(fn ->
          case socket.assigns.salesforce_credential do
            nil -> {:ok, []}
            credential -> SalesforceApi.search_contacts(credential, query)
          end
        end)

        # Wait for both searches to complete
        hubspot_result = Task.await(hubspot_task, 10_000)
        salesforce_result = Task.await(salesforce_task, 10_000)

        # Merge results and handle errors - show results from any successful searches
        case {hubspot_result, salesforce_result} do
          {{:ok, hubspot_contacts}, {:ok, salesforce_contacts}} ->
            # Both succeeded - merge and deduplicate contacts
            merged_contacts = merge_contacts(hubspot_contacts, salesforce_contacts, query)

            {:noreply, assign(socket,
              contacts: merged_contacts,
              searching: false,
              error: nil,
              query: query,
              dropdown_open: true
            )}

          {{:ok, hubspot_contacts}, {:error, _}} ->
            # Only HubSpot succeeded - add source indicator and use results
            hubspot_with_source = Enum.map(hubspot_contacts, &Map.put(&1, :source, "HubSpot"))

            {:noreply, assign(socket,
              contacts: hubspot_with_source,
              searching: false,
              error: nil,
              query: query,
              dropdown_open: true
            )}

          {{:error, _}, {:ok, salesforce_contacts}} ->
            # Only Salesforce succeeded - add source indicator and use results
            salesforce_with_source = Enum.map(salesforce_contacts, &Map.put(&1, :source, "Salesforce"))

            {:noreply, assign(socket,
              contacts: salesforce_with_source,
              searching: false,
              error: nil,
              query: query,
              dropdown_open: true
            )}

          {{:error, hubspot_error}, {:error, salesforce_error}} ->
            # Both failed
            {:noreply, assign(socket,
              error: "Both HubSpot and Salesforce searches failed: HubSpot: #{inspect(hubspot_error)}, Salesforce: #{inspect(salesforce_error)}",
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
  def handle_event("toggle_tab", %{"tab" => tab}, socket) do
    tab = if tab in ["chat", "history"], do: tab, else: "chat"

    socket =
      socket
      |> assign(:active_tab, tab)
      |> maybe_refresh_history(tab)

    socket =
      if tab == "chat" do
        push_event(socket, "scroll_to_bottom", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    socket = close_current_session(socket)

    meeting = socket.assigns[:meeting]
    user = socket.assigns[:current_user]

    socket =
      if meeting && user do
        new_session = create_chat_session!(meeting, user)
        chat_sessions = load_chat_sessions(meeting, user)
        selected_session_id = normalize_selected_session_id(nil, chat_sessions)
        history_messages =
          if selected_session_id do
            load_messages_for_session_id(selected_session_id, chat_sessions)
          else
            []
          end

        assign(socket,
          chat_session: new_session,
          messages: [],
          active_tab: "chat",
          selected_session_id: selected_session_id,
          history_messages: history_messages,
          chat_sessions: chat_sessions
        )
      else
        socket
      end

    {:noreply, push_event(socket, "clear_input", %{})}
  end

  @impl true
  def handle_event("select_history_session", %{"id" => id}, socket) do
    session_id = String.to_integer(id)

    session = Enum.find(socket.assigns.chat_sessions, fn s -> s.id == session_id end)

    history_messages =
      load_messages_for_session_id(session_id, socket.assigns.chat_sessions)

    socket =
      assign(socket,
        active_tab: "chat",
        selected_session_id: session_id,
        history_messages: history_messages,
        messages: history_messages,
        chat_session: session || socket.assigns.chat_session
      )

    {:noreply, push_event(socket, "scroll_to_bottom", %{})}
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, fn c ->
      get_contact_field(c, :id) == contact_id
    end)

    if contact do
      # Extract first name from display name
      first_name = extract_first_name(get_contact_field(contact, :display_name))

      # Send data to JavaScript hook to update the input
      socket = push_event(socket, "update_contact_highlight", %{
        contact_id: get_contact_field(contact, :id),
        display_name: get_contact_field(contact, :display_name),
        first_name: "@" <> first_name
      })

      {:noreply, assign(socket, selected_contact_id: get_contact_field(contact, :id), dropdown_open: false, query: "")}
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)
    {socket, _session} = ensure_active_session(socket)

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

        # Search for contact by name in both CRMs
        hubspot_task = Task.async(fn ->
          case socket.assigns.hubspot_credential do
            nil -> {:ok, []}
            credential -> HubspotApi.search_contacts(credential, contact_name)
          end
        end)

        salesforce_task = Task.async(fn ->
          case socket.assigns.salesforce_credential do
            nil -> {:ok, []}
            credential -> SalesforceApi.search_contacts(credential, contact_name)
          end
        end)

        # Wait for both searches to complete
        hubspot_result = Task.await(hubspot_task, 10_000)
        salesforce_result = Task.await(salesforce_task, 10_000)

        # Merge results and handle errors
        case {hubspot_result, salesforce_result} do
          {{:ok, hubspot_contacts}, {:ok, salesforce_contacts}} ->
            # Merge and deduplicate contacts
            merged_contacts = merge_contacts(hubspot_contacts, salesforce_contacts, contact_name)

            if Enum.any?(merged_contacts) do
              contact = Enum.at(merged_contacts, 0)

              # Normalize contact to use string keys (consistent with loaded messages)
              normalized_contact = %{
                "id" => get_contact_field(contact, :id),
                "display_name" => get_contact_field(contact, :display_name),
                "email" => get_contact_field(contact, :email),
                "source" => get_contact_field(contact, :source)
              }

              # Save user message to database
              save_message_to_db(
                socket.assigns.meeting,
                socket.assigns.current_user,
                socket.assigns.chat_session,
                "user",
                message,
                normalized_contact
              )

              # Add user message to history WITH contact info
              user_message = %{
                type: "user",
                content: message,
                timestamp: format_timestamp(DateTime.utc_now()),
                contact: normalized_contact
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
              |> push_event("scroll_to_bottom", %{})

              # Generate AI response
              generate_and_add_ai_response(socket, normalized_contact, message)
            else
              {:noreply, assign(socket, error: "No contact found with name: #{contact_name}")}
            end

          {{:ok, _}, {:error, salesforce_error}} ->
            # HubSpot succeeded, Salesforce failed - use HubSpot results
            case hubspot_result do
              {:ok, hubspot_contacts} ->
                if Enum.any?(hubspot_contacts) do
                  contact = Enum.at(hubspot_contacts, 0)
                  normalized_contact = %{
                    "id" => get_contact_field(contact, :id),
                    "display_name" => get_contact_field(contact, :display_name),
                    "email" => get_contact_field(contact, :email),
                    "source" => "HubSpot"
                  }

                  save_message_to_db(socket.assigns.meeting, socket.assigns.current_user, "user", message, normalized_contact)

                  user_message = %{
                    type: "user",
                    content: message,
                    timestamp: format_timestamp(DateTime.utc_now()),
                    contact: normalized_contact
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
                  |> push_event("scroll_to_bottom", %{})

                  generate_and_add_ai_response(socket, normalized_contact, message)
                else
                  {:noreply, assign(socket, error: "No contact found with name: #{contact_name}")}
                end

              {:error, reason} ->
                {:noreply, assign(socket, error: "Failed to search contacts: #{inspect(reason)}")}
            end

          {{:error, hubspot_error}, {:ok, salesforce_contacts}} ->
            # Salesforce succeeded, HubSpot failed - use Salesforce results
            if Enum.any?(salesforce_contacts) do
              contact = Enum.at(salesforce_contacts, 0)
              normalized_contact = %{
                "id" => get_contact_field(contact, :id),
                "display_name" => get_contact_field(contact, :display_name),
                "email" => get_contact_field(contact, :email),
                "source" => "Salesforce"
              }

              save_message_to_db(socket.assigns.meeting, socket.assigns.current_user, "user", message, normalized_contact)

              user_message = %{
                type: "user",
                content: message,
                timestamp: format_timestamp(DateTime.utc_now()),
                contact: normalized_contact
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
              |> push_event("scroll_to_bottom", %{})

              generate_and_add_ai_response(socket, normalized_contact, message)
            else
              {:noreply, assign(socket, error: "No contact found with name: #{contact_name}")}
            end

          {{:error, hubspot_error}, {:error, salesforce_error}} ->
            # Both failed
            {:noreply, assign(socket, error: "Failed to search contacts in both HubSpot and Salesforce: HubSpot: #{inspect(hubspot_error)}, Salesforce: #{inspect(salesforce_error)}")}
        end
      else
        {:noreply, assign(socket, error: "Please mention a contact with @name")}
      end
    end
  end

  defp generate_and_add_ai_response(socket, contact, question) do
    # Get full contact data from the appropriate CRM based on source
    source = contact["source"] || "HubSpot" # Default to HubSpot for backward compatibility

    full_contact_result =
      case source do
        "HubSpot" ->
          case socket.assigns.hubspot_credential do
            nil -> {:error, :no_credential}
            credential -> HubspotApi.get_contact(credential, contact["id"])
          end

        "Salesforce" ->
          case socket.assigns.salesforce_credential do
            nil -> {:error, :no_credential}
            credential -> SalesforceApi.get_contact(credential, contact["id"])
          end

        _ ->
          {:error, :unknown_source}
      end

    case full_contact_result do
      {:ok, full_contact} ->
        # Normalize full_contact to use string keys
        normalized_full_contact = %{
          "id" => get_contact_field(full_contact, :id),
          "display_name" => get_contact_field(full_contact, :display_name),
          "email" => get_contact_field(full_contact, :email),
          "source" => source
        }

        # Generate AI response
        case AIContentGeneratorApi.generate_contact_answer(socket.assigns.meeting, full_contact, question) do
          {:ok, response} ->
            # Save AI message to database
            save_message_to_db(
              socket.assigns.meeting,
              socket.assigns.current_user,
              socket.assigns.chat_session,
              "ai",
              response,
              normalized_full_contact
            )

            ai_message = %{
              type: "ai",
              content: response,
              timestamp: format_timestamp(DateTime.utc_now()),
              contact: normalized_full_contact
            }

            {:noreply, assign(socket,
              messages: socket.assigns.messages ++ [ai_message],
              loading: false,
              message: ""
            )
            |> push_event("scroll_to_bottom", %{})}

          {:error, reason} ->
            {:api_error, _status, body} = reason
            message = get_in(body, ["error", "message"])
            error_message = %{
              type: "ai",
              content: "I'm sorry, I couldn't generate a response: {#{message}}",
              timestamp: format_timestamp(DateTime.utc_now()),
              contact: nil
            }

            # Save error message to database
            save_message_to_db(
              socket.assigns.meeting,
              socket.assigns.current_user,
              socket.assigns.chat_session,
              "ai",
              error_message.content,
              nil
            )

            {:noreply, assign(socket,
              messages: socket.assigns.messages ++ [error_message],
              loading: false,
              message: ""
            )
            |> push_event("scroll_to_bottom", %{})}
        end

      {:error, :no_credential} ->
        error_message = %{
          type: "ai",
          content: "I'm sorry, I couldn't retrieve the contact information: No #{source} credentials available.",
          timestamp: format_timestamp(DateTime.utc_now()),
          contact: nil
        }

        # Save error message to database
        save_message_to_db(socket.assigns.meeting, socket.assigns.current_user, "ai", error_message.content, nil)

        {:noreply, assign(socket,
          messages: socket.assigns.messages ++ [error_message],
          loading: false,
          message: ""
        )
        |> push_event("scroll_to_bottom", %{})}

      {:error, :unknown_source} ->
        error_message = %{
          type: "ai",
          content: "I'm sorry, I couldn't retrieve the contact information: Unknown contact source.",
          timestamp: format_timestamp(DateTime.utc_now()),
          contact: nil
        }

        # Save error message to database
        save_message_to_db(socket.assigns.meeting, socket.assigns.current_user, "ai", error_message.content, nil)

        {:noreply, assign(socket,
          messages: socket.assigns.messages ++ [error_message],
          loading: false,
          message: ""
        )
        |> push_event("scroll_to_bottom", %{})}

      {:error, reason} ->
        error_message = %{
          type: "ai",
          content: "I'm sorry, I couldn't retrieve the contact information from #{source}: #{inspect(reason)}",
          timestamp: format_timestamp(DateTime.utc_now()),
          contact: nil
        }

        # Save error message to database
        save_message_to_db(
          socket.assigns.meeting,
          socket.assigns.current_user,
          socket.assigns.chat_session,
          "ai",
          error_message.content,
          nil
        )

        {:noreply, assign(socket,
          messages: socket.assigns.messages ++ [error_message],
          loading: false,
          message: ""
        )
        |> push_event("scroll_to_bottom", %{})}
    end
  end

  defp format_timestamp(datetime) do
    hour = datetime.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute = datetime.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{hour}:#{minute}"
  end

  defp parse_message_with_highlights(message_content, contact) do
    # Handle both atom keys (from structs) and string keys (from database/JSON)
    display_name = get_contact_field(contact, :display_name)
    first_name = extract_first_name(display_name)

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
    case String.split(display_name || "", " ") do
      [first_name | _] -> first_name
      [] -> display_name
    end
  end
defp merge_contacts(hubspot_contacts, salesforce_contacts, _query) do
    # Add source indicators to contacts
    hubspot_with_source = Enum.map(hubspot_contacts, &Map.put(&1, :source, "HubSpot"))
    salesforce_with_source = Enum.map(salesforce_contacts, &Map.put(&1, :source, "Salesforce"))

    # Combine all contacts
    all_contacts = hubspot_with_source ++ salesforce_with_source

    # Deduplicate by email address (case-insensitive)
    all_contacts
    |> Enum.group_by(fn contact ->
      email = get_contact_field(contact, :email) || ""
      String.downcase(email)
    end)
    |> Enum.map(fn {_email, contacts} ->
      # If multiple contacts have same email, prefer HubSpot, otherwise take first
      Enum.find(contacts, &(&1.source == "HubSpot")) || List.first(contacts)
    end)
    |> Enum.sort_by(&get_contact_field(&1, :display_name), &<=/2)
  end

  defp mention_label(part) do
    part
    |> String.trim_leading("@")
    |> String.trim()
  end

  defp mention_initial(part) do
    part
    |> mention_label()
    |> String.first()
    |> case do
      nil -> "?"
      initial -> String.upcase(initial)
    end
  end

  defp load_available_sources(user) do
    if is_nil(user) do
      []
    else
    providers =
      user
      |> Accounts.list_user_credentials()
      |> Enum.map(& &1.provider)
      |> Enum.uniq()

    @source_order
    |> Enum.filter(&(&1 in providers))
    end
  end

  defp sources_for_message(message, available_sources) do
    content = String.downcase(message.content || "")

    detected =
      @source_keywords
      |> Enum.filter(fn {_source, keywords} ->
        Enum.any?(keywords, &String.contains?(content, &1))
      end)
      |> Enum.map(fn {source, _} -> source end)

    inferred =
      if message.contact && "hubspot" in available_sources do
        ["hubspot"]
      else
        []
      end

    (detected ++ inferred)
    |> Enum.uniq()
    |> Enum.filter(&(&1 in available_sources))
  end

  defp source_label("hubspot"), do: "HubSpot"
  defp source_label("salesforce"), do: "Salesforce"
  defp source_label("facebook"), do: "Facebook"
  defp source_label("linkedin"), do: "LinkedIn"
  defp source_label("google"), do: "Google"
  defp source_label(other), do: String.capitalize(other)

  defp source_initial("hubspot"), do: "H"
  defp source_initial("salesforce"), do: "S"
  defp source_initial("facebook"), do: "F"
  defp source_initial("linkedin"), do: "L"
  defp source_initial("google"), do: "G"
  defp source_initial(_), do: "?"

  defp source_color_class("hubspot"), do: "bg-[#ff7a59]"
  defp source_color_class("salesforce"), do: "bg-[#00a1e0]"
  defp source_color_class("facebook"), do: "bg-[#1877f2]"
  defp source_color_class("linkedin"), do: "bg-[#0a66c2]"
  defp source_color_class("google"), do: "bg-[#4285f4]"
  defp source_color_class(_), do: "bg-slate-400"

  defp get_contact_field(contact, field) when is_atom(field) do
    string_key = Atom.to_string(field)
    contact[string_key] || contact[field] || Map.get(contact, field)
  end

  defp load_messages_for_session(nil), do: []

  defp load_messages_for_session(session) do
    SocialScribe.Meetings.list_chat_messages_for_session(session)
    |> Enum.map(fn message ->
      %{
        type: message.message_type,
        content: message.content,
        timestamp: format_timestamp(message.timestamp),
        contact: (if message.contact_data, do: message.contact_data, else: nil)
      }
    end)
  end

  defp load_chat_sessions(nil, _user), do: []
  defp load_chat_sessions(_meeting, nil), do: []

  defp load_chat_sessions(meeting, user) do
    meeting
    |> SocialScribe.Meetings.list_chat_sessions(user)
    |> Enum.reduce([], fn session, acc ->
      session =
        if is_nil(session.preview) or session.preview == "" do
          case SocialScribe.Meetings.get_first_chat_message_for_session(session) do
            nil -> nil
            message -> %{session | preview: extract_preview(message.content)}
          end
        else
          session
        end

      case session do
        nil -> acc
        session -> [session | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp load_messages_for_session_id(session_id, chat_sessions) do
    session = Enum.find(chat_sessions, fn s -> s.id == session_id end)
    load_messages_for_session(session)
  end

  defp normalize_selected_session_id(selected_session_id, chat_sessions) do
    case Enum.find(chat_sessions, fn s -> s.id == selected_session_id end) do
      nil ->
        case List.first(chat_sessions) do
          nil -> nil
          session -> session.id
        end

      _session ->
        selected_session_id
    end
  end

  defp ensure_active_session(socket) do
    meeting = socket.assigns[:meeting]
    user = socket.assigns[:current_user]
    existing_session = socket.assigns[:chat_session]

    cond do
      meeting && user && existing_session &&
          existing_session.meeting_id == meeting.id &&
          existing_session.user_id == user.id ->
        {socket, existing_session}

      meeting && user ->
        session =
          SocialScribe.Meetings.get_active_chat_session(meeting, user) ||
            create_chat_session!(meeting, user)

        {assign(socket, :chat_session, session), session}

      true ->
        {assign(socket, :chat_session, nil), nil}
    end
  end

  defp create_chat_session!(meeting, user) do
    {:ok, session} =
      SocialScribe.Meetings.create_chat_session(%{
        meeting_id: meeting.id,
        user_id: user.id,
        started_at: DateTime.utc_now()
      })

    session
  end

  defp maybe_refresh_history(socket, "history") do
    chat_sessions = load_chat_sessions(socket.assigns.meeting, socket.assigns.current_user)
    selected_session_id =
      normalize_selected_session_id(socket.assigns.selected_session_id, chat_sessions)

    history_messages =
      if selected_session_id do
        load_messages_for_session_id(selected_session_id, chat_sessions)
      else
        []
      end

    assign(socket,
      chat_sessions: chat_sessions,
      selected_session_id: selected_session_id,
      history_messages: history_messages
    )
  end

  defp maybe_refresh_history(socket, _tab), do: socket

  defp close_current_session(%{assigns: %{chat_session: nil}} = socket), do: socket

  defp close_current_session(socket) do
    session = socket.assigns.chat_session
    preview = extract_preview_from_messages(socket.assigns.messages)

    _ =
      SocialScribe.Meetings.close_chat_session(session, %{
        preview: session.preview || preview
      })

    socket
  end

  defp extract_preview_from_messages(messages) do
    messages
    |> Enum.find(fn message -> message.type == "user" and is_binary(message.content) end)
    |> case do
      nil -> nil
      message -> extract_preview(message.content)
    end
  end

  defp maybe_update_session_preview(session, "user", content) do
    if is_nil(session.preview) or session.preview == "" do
      preview = extract_preview(content)
      _ = SocialScribe.Meetings.update_chat_session(session, %{preview: preview})
    end
  end

  defp maybe_update_session_preview(_session, _message_type, _content), do: :ok

  defp extract_preview(content) when is_binary(content) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.split(~r/[.!?]/, parts: 2)
    |> List.first()
    |> case do
      nil -> nil
      "" -> nil
      sentence -> String.slice(sentence, 0, 120)
    end
  end

  defp extract_preview(_), do: nil

  defp save_message_to_db(meeting, user, chat_session, message_type, content, contact \\ nil) do
    now = DateTime.utc_now()
    chat_session = chat_session || create_chat_session!(meeting, user)

    contact_data = if contact, do: %{
      "id" => contact["id"],
      "display_name" => contact["display_name"],
      "email" => contact["email"]
    }, else: nil

    attrs = %{
      meeting_id: meeting.id,
      user_id: user.id,
      message_type: message_type,
      content: content,
      contact_id: contact && contact["id"],
      contact_data: contact_data,
      timestamp: now,
      chat_date: DateTime.to_date(now),
      chat_session_id: chat_session.id
    }

    case SocialScribe.Meetings.create_chat_message(attrs) do
      {:ok, _chat_message} ->
        maybe_update_session_preview(chat_session, message_type, content)
        :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_session_date(%DateTime{} = datetime) do
    date = DateTime.to_date(datetime)
    format_date(date)
  end

  defp format_selected_session_label(chat_sessions, selected_session_id) do
    case Enum.find(chat_sessions, fn s -> s.id == selected_session_id end) do
      nil -> ""
      session -> format_session_date(session.started_at)
    end
  end

  defp format_date(%Date{year: year, month: month, day: day}) do
    month_name =
      [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December"
      ]
      |> Enum.at(month - 1, "Unknown")

    "#{month_name} #{day}, #{year}"
  end
end

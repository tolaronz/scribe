defmodule SocialScribe.Meetings.MeetingChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Meetings.Meeting
  alias SocialScribe.Accounts.User

  schema "meeting_chat_messages" do
    field :message_type, :string
    field :content, :string
    field :contact_id, :string
    field :contact_data, :map
    field :timestamp, :utc_datetime

    belongs_to :meeting, Meeting
    belongs_to :user, User

    timestamps()
  end

  def changeset(meeting_chat_message, attrs) do
    meeting_chat_message
    |> cast(attrs, [
      :meeting_id,
      :user_id,
      :message_type,
      :content,
      :contact_id,
      :contact_data,
      :timestamp
    ])
    |> validate_required([
      :meeting_id,
      :user_id,
      :message_type,
      :content,
      :timestamp
    ])
    |> validate_inclusion(:message_type, ["user", "ai"])
  end
end

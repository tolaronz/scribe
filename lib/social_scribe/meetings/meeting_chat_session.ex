defmodule SocialScribe.Meetings.MeetingChatSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Meetings.Meeting
  alias SocialScribe.Accounts.User

  schema "meeting_chat_sessions" do
    field :preview, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :meeting, Meeting
    belongs_to :user, User

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:meeting_id, :user_id, :preview, :started_at, :ended_at])
    |> validate_required([:meeting_id, :user_id, :started_at])
  end
end

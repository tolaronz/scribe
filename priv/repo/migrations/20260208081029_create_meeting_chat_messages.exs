defmodule SocialScribe.Repo.Migrations.CreateMeetingChatMessages do
  use Ecto.Migration

  def change do
    create table(:meeting_chat_messages) do
      add :meeting_id, references(:meetings, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :message_type, :string, null: false
      add :content, :text, null: false
      add :contact_id, :string
      add :contact_data, :map
      add :timestamp, :utc_datetime, null: false

      timestamps()
    end

    create index(:meeting_chat_messages, [:meeting_id])
    create index(:meeting_chat_messages, [:user_id])
    create index(:meeting_chat_messages, [:meeting_id, :user_id])
    create index(:meeting_chat_messages, [:meeting_id, :user_id, :inserted_at])
  end
end

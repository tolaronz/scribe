defmodule SocialScribe.Repo.Migrations.AddChatDateToMeetingChatMessages do
  use Ecto.Migration

  def up do
    alter table(:meeting_chat_messages) do
      add :chat_date, :date
    end

    execute("""
    UPDATE meeting_chat_messages
    SET chat_date = ("timestamp" AT TIME ZONE 'UTC')::date
    WHERE chat_date IS NULL
    """)

    alter table(:meeting_chat_messages) do
      modify :chat_date, :date, null: false
    end

    create index(:meeting_chat_messages, [:meeting_id, :user_id, :chat_date])
  end

  def down do
    drop index(:meeting_chat_messages, [:meeting_id, :user_id, :chat_date])

    alter table(:meeting_chat_messages) do
      remove :chat_date
    end
  end
end

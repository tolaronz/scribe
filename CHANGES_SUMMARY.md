# Scribe Update: Chat Component and Salesforce Integration

## Overview

This update introduces a comprehensive chat interface for meeting interactions and adds Salesforce CRM integration alongside the existing HubSpot integration. The changes include database schema updates, new API modules, UI components, and enhanced meeting functionality.

## What Has Been Changed

### 1. Database Schema Changes

#### New Table: `meeting_chat_messages`
- **Purpose**: Stores chat messages between users and AI assistant during meeting interactions
- **Fields**:
  - `meeting_id`: Foreign key to meetings table
  - `user_id`: Foreign key to users table  
  - `message_type`: Either "user" or "ai"
  - `content`: The message text content
  - `contact_id`: Optional contact reference for CRM integrations
  - `contact_data`: JSON field storing contact information
  - `timestamp`: UTC datetime of message creation
  - `chat_date`: Date extracted from timestamp for efficient querying
  - `chat_session_id`: Foreign key to meeting_chat_sessions table

#### New Table: `meeting_chat_sessions`
- **Purpose**: Tracks chat sessions with start/end times and session previews
- **Fields**:
  - `meeting_id`: Foreign key to meetings table
  - `user_id`: Foreign key to users table
  - `preview`: Text preview of the chat session
  - `started_at`: UTC datetime when session started
  - `ended_at`: UTC datetime when session ended (nullable for active sessions)

#### Migration Files:
- `20260208081029_create_meeting_chat_messages.exs`: Creates the chat messages table
- `20260209071818_oban_install.exs`: Placeholder for Oban job queue installation
- `20260209090000_add_chat_date_to_meeting_chat_messages.exs`: Adds chat_date field and indexes
- `20260209093000_add_meeting_chat_sessions.exs`: Creates chat sessions table with relationships

### 2. New API Modules

#### Salesforce Integration
- **`lib/social_scribe/salesforce_api.ex`**: Complete Salesforce CRM API client
  - Contact search and retrieval
  - Contact updates with automatic token refresh
  - SOQL/SOSL query support
  - Error handling for authentication issues

- **`lib/social_scribe/salesforce_api_behaviour.ex`**: Behavior interface for Salesforce API

- **`lib/social_scribe/salesforce_suggestions.ex`**: AI-powered suggestion generation for Salesforce updates

- **`lib/social_scribe/salesforce_token_refresher.ex`**: Automatic token refresh functionality

#### Enhanced HubSpot API
- **`lib/social_scribe/hubspot_api.ex`**: Enhanced with contact search capabilities
- **`lib/social_scribe/hubspot_api_behaviour.ex`**: Updated behavior interface

### 3. UI Components

#### Chat Interface
- **`lib/social_scribe_web/live/meeting_live/chat_component.ex`**: 
  - Real-time chat interface for meeting interactions
  - Contact mention system (@name syntax)
  - AI response generation
  - Message history with contact context
  - Loading states and error handling

#### Salesforce Modal
- **`lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex`**:
  - Contact selection interface
  - AI-generated update suggestions
  - Field-by-field update controls
  - Integration with Salesforce API

#### Frontend Assets
- **`assets/js/mention_input.js`**: JavaScript for contact mention functionality
  - Contenteditable input handling
  - Contact highlighting
  - Dropdown navigation
  - Form submission handling

### 4. Enhanced Meeting Interface

#### Updated Files:
- **`lib/social_scribe_web/live/meeting_live/show.ex`**: Enhanced with chat functionality
- **`lib/social_scribe_web/live/meeting_live/show.html.heex`**: Updated UI with collapsible chat panel
- **`lib/social_scribe/meetings.ex`**: Added chat message management functions

#### New Features:
- Collapsible chat panel on meeting detail page
- Real-time chat with AI assistant
- Contact mention and highlighting
- Message persistence and history

### 5. Authentication Integration

#### New OAuth Strategy
- **`lib/ueberauth/strategy/salesforce.ex`**: Salesforce OAuth2 authentication
- **`lib/ueberauth/strategy/salesforce/oauth.ex`**: OAuth configuration

### 6. Configuration Updates

#### Environment Configuration
- **`config/config.exs`**: Added Salesforce API configuration
- **`config/runtime.exs`**: Runtime environment variables for Salesforce

## Database Migration Changes

### Migration 20260208081029: Create Meeting Chat Messages

```sql
CREATE TABLE meeting_chat_messages (
  id BIGSERIAL PRIMARY KEY,
  meeting_id BIGINT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message_type VARCHAR(10) NOT NULL,
  content TEXT NOT NULL,
  contact_id VARCHAR,
  contact_data JSONB,
  timestamp TIMESTAMPTZ NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_meeting_chat_messages_meeting_id ON meeting_chat_messages(meeting_id);
CREATE INDEX idx_meeting_chat_messages_user_id ON meeting_chat_messages(user_id);
CREATE INDEX idx_meeting_chat_messages_meeting_user ON meeting_chat_messages(meeting_id, user_id);
CREATE INDEX idx_meeting_chat_messages_meeting_user_created ON meeting_chat_messages(meeting_id, user_id, inserted_at);
```

### Migration 20260209090000: Add Chat Date to Meeting Chat Messages

```sql
-- Add chat_date column
ALTER TABLE meeting_chat_messages ADD COLUMN chat_date DATE;

-- Populate chat_date from timestamp
UPDATE meeting_chat_messages
SET chat_date = ("timestamp" AT TIME ZONE 'UTC')::date
WHERE chat_date IS NULL;

-- Make chat_date non-nullable
ALTER TABLE meeting_chat_messages ALTER COLUMN chat_date SET NOT NULL;

-- Add index for date-based queries
CREATE INDEX idx_meeting_chat_messages_meeting_user_date ON meeting_chat_messages(meeting_id, user_id, chat_date);
```

### Migration 20260209093000: Add Meeting Chat Sessions

```sql
-- Create meeting_chat_sessions table
CREATE TABLE meeting_chat_sessions (
  id BIGSERIAL PRIMARY KEY,
  meeting_id BIGINT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  preview TEXT,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

-- Add indexes for session queries
CREATE INDEX idx_meeting_chat_sessions_meeting_user ON meeting_chat_sessions(meeting_id, user_id);
CREATE INDEX idx_meeting_chat_sessions_meeting_user_ended ON meeting_chat_sessions(meeting_id, user_id, ended_at);

-- Add chat_session_id to meeting_chat_messages
ALTER TABLE meeting_chat_messages ADD COLUMN chat_session_id BIGINT REFERENCES meeting_chat_sessions(id) ON DELETE CASCADE;

-- Create sessions for existing messages and link them
WITH sessions AS (
  INSERT INTO meeting_chat_sessions (meeting_id, user_id, preview, started_at, ended_at, inserted_at, updated_at)
  SELECT meeting_id, user_id, NULL, MIN(timestamp), MAX(timestamp), NOW(), NOW()
  FROM meeting_chat_messages
  GROUP BY meeting_id, user_id
  RETURNING id, meeting_id, user_id
)
UPDATE meeting_chat_messages m
SET chat_session_id = s.id
FROM sessions s
WHERE m.meeting_id = s.meeting_id AND m.user_id = s.user_id AND m.chat_session_id IS NULL;

-- Make chat_session_id non-nullable
ALTER TABLE meeting_chat_messages ALTER COLUMN chat_session_id SET NOT NULL;

-- Add index for session-based queries
CREATE INDEX idx_meeting_chat_messages_session_id ON meeting_chat_messages(chat_session_id);
```

### Migration 20260209071818: Oban Installation

This is a placeholder migration for installing Oban job queue. The actual implementation will be added in a subsequent update.

## Testing Workflow

### 1. Database Migration Testing

```bash
# Run migrations
mix ecto.migrate

# Verify table creation
psql -d your_database_name -c "\d meeting_chat_messages"

# Test chat message creation
mix run -e "SocialScribe.Meetings.create_chat_message(%{meeting_id: 1, user_id: 1, message_type: \"user\", content: \"Test message\", timestamp: DateTime.utc_now()})"
```

### 2. Salesforce Integration Testing

#### Prerequisites:
- Salesforce Developer account
- Connected App configured with OAuth2
- Environment variables set:
  - `SALESFORCE_CLIENT_ID`
  - `SALESFORCE_CLIENT_SECRET`
  - `SALESFORCE_REDIRECT_URI`

#### Test Steps:

1. **Authentication Flow**:
   ```bash
   # Navigate to user settings
   # Click "Connect Salesforce" button
   # Complete OAuth flow
   # Verify credential is saved
   ```

2. **Contact Search**:
   ```elixir
   # In IEx console
   {:ok, credential} = SocialScribe.Accounts.get_user_credential_by_provider(user_id, "salesforce")
   {:ok, contacts} = SocialScribe.SalesforceApi.search_contacts(credential, "John Doe")
   ```

3. **Contact Updates**:
   ```elixir
   # Test updating a contact
   updates = %{"email" => "new@example.com", "phone" => "555-1234"}
   SocialScribe.SalesforceApi.update_contact(credential, contact_id, updates)
   ```

### 3. Chat Component Testing

#### Manual Testing:

1. **Navigate to Meeting Detail**:
   - Go to `/dashboard/meetings/{meeting_id}`
   - Verify chat panel appears on right side

2. **Test Chat Functionality**:
   - Type a message in the chat input
   - Verify message appears in history
   - Test contact mentions (@name syntax)
   - Verify dropdown appears for contact selection

3. **Test AI Responses**:
   - Ask a question about a contact
   - Verify AI generates appropriate response
   - Check that responses are saved to database

4. **Test Chat Persistence**:
   - Refresh the page
   - Verify chat history is preserved
   - Test across different meetings

5. **Test Chat Sessions**:
   - Start a new chat session by sending a message
   - Verify session is created with proper start time
   - Send multiple messages and verify they're linked to the same session
   - Close the session and verify end time is set
   - Test session preview generation

6. **Test Date-based Chat Navigation**:
   - Send messages on different dates
   - Verify chat sessions are organized by date
   - Test switching between different chat dates

### 4. Integration Testing

#### End-to-End Workflow:

1. **Complete Meeting Flow**:
   ```bash
   # 1. Record a meeting (existing functionality)
   # 2. Generate AI follow-up email (existing functionality)
   # 3. Open meeting detail page
   # 4. Use chat to ask about contacts
   # 5. Generate Salesforce/HubSpot updates
   # 6. Verify updates are applied to CRM
   ```

2. **Cross-Integration Testing**:
   - Test HubSpot and Salesforce integrations independently
   - Verify both can be connected simultaneously
   - Test switching between integrations

### 5. Automated Testing

#### Run Test Suite:
```bash
# Run all tests
mix test

# Run specific test files
mix test test/social_scribe/salesforce_api_test.exs
mix test test/social_scribe/salesforce_suggestions_test.exs
mix test test/social_scribe/salesforce_token_refresher_test.exs
mix test test/social_scribe_web/live/meeting_live/chat_component_test.exs

# Run with coverage
mix test --cover
```

#### Test Chat Session Functionality:
```bash
# Test chat session management
mix test test/social_scribe/meetings_test.exs --only chat_sessions

# Test chat message functionality
mix test test/social_scribe/meetings_test.exs --only chat_messages

# Test date-based chat queries
mix test test/social_scribe/meetings_test.exs --only chat_dates
```

## Configuration Requirements

### Environment Variables

Add to your `.env` file or environment:

```bash
# Salesforce Configuration
SALESFORCE_CLIENT_ID=your_salesforce_client_id
SALESFORCE_CLIENT_SECRET=your_salesforce_client_secret
SALESFORCE_REDIRECT_URI=https://your-domain.com/auth/salesforce/callback
SALESFORCE_SITE=https://login.salesforce.com
SALESFORCE_API_VERSION=v59.0

# Database (existing)
DATABASE_URL=postgresql://user:password@localhost/social_scribe_dev
```

### Dependencies

Ensure these dependencies are in `mix.exs`:

```elixir
defp deps do
  [
    # Existing dependencies...
    {:oban, "~> 2.18"},  # For job queue (future implementation)
    {:tesla, "~> 1.7"},  # HTTP client for API calls
    {:jason, "~> 1.4"}   # JSON encoding/decoding
  ]
end
```

## Breaking Changes

### None

This update is backward compatible. Existing functionality remains unchanged while adding new features.

## Performance Considerations

### Database Indexes
- Added appropriate indexes for chat message queries
- Optimized for meeting-specific message retrieval

### API Rate Limiting
- Salesforce API calls include error handling for rate limits
- Automatic retry logic for authentication errors

### Frontend Performance
- Chat messages are loaded on-demand
- Dropdown results are cached during session

## Security Considerations

### Data Privacy
- Chat messages are scoped to meetings and users
- Contact data is stored securely with proper access controls
- OAuth tokens are encrypted in database

### Input Validation
- All user inputs are validated before processing
- SQL injection protection through Ecto
- XSS protection through Phoenix HTML sanitization

## Rollback Plan

### Database Rollback
```bash
# Rollback chat messages table
mix ecto.rollback --step 1

# Or specific migration
mix ecto.rollback --to 20260208081029
```

### Code Rollback
- Remove Salesforce integration files
- Revert meeting live view changes
- Remove chat component references

## Monitoring and Observability

### Logging
- Salesforce API calls are logged with appropriate levels
- Authentication errors are tracked
- Chat interactions are logged for debugging

### Metrics
- Chat message creation rate
- API response times
- Authentication success/failure rates

## Future Enhancements

### Planned Features
1. **Oban Job Queue**: Background processing for AI content generation
2. **Multi-CRM Support**: Additional CRM integrations
3. **Chat Analytics**: Usage statistics and insights
4. **Rich Text Support**: Enhanced message formatting
5. **File Attachments**: Support for document sharing in chat

### Technical Debt
- Complete Oban migration implementation
- Unit test coverage for new components
- Performance optimization for large contact lists
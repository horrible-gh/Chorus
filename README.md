# Chorus

**Chorus is a local multi-agent AI workspace for coordinating prompts, agents, presets, and model routing in one real-time chat environment.**

It is built for developers who use multiple AI assistants and CLI tools, but do not want their prompts, tasks, rooms, and agent roles scattered across separate windows, terminals, and chat histories.

Chorus provides a local-first workspace where you can organize AI agents, route work by purpose, manage reusable presets, and keep conversations moving in real time.

![Chorus preview](docs/assets/preview.png)

---

## Why Chorus?

Modern AI-assisted development often means using several tools at once:

- one assistant for architecture
- one for coding
- one for debugging
- one for documentation
- one for research
- one for repetitive task execution

That workflow becomes messy fast.

Prompts get duplicated.  
Context gets lost.  
Agent roles become unclear.  
CLI sessions live outside the main workspace.  
Useful results are hard to organize after the fact.

**Chorus is an attempt to make that workflow manageable.**

Instead of treating each AI tool as an isolated chat window, Chorus treats them as participants in a coordinated workspace.

---

## What Chorus Does

Chorus currently focuses on the foundation of a multi-agent AI workspace:

- **Room-based real-time chat**
  - WebSocket-powered room updates
  - multi-user / multi-agent conversation structure

- **Agent management**
  - create and manage agents
  - define agent roles and behavior
  - prepare agents for task-specific workflows

- **Model and task routing**
  - route work based on purpose, agent, or preset
  - organize model-specific workflows
  - prepare a unified interface for multiple AI backends

- **Preset management**
  - reuse prompt and workflow configurations
  - reduce repeated setup across sessions

- **Authentication**
  - JWT-based login
  - user registration
  - 2FA support

- **File handling**
  - upload and download support
  - foundation for file-aware AI workflows

- **Local-first architecture**
  - designed to run on your own machine or server
  - suitable for personal AI workspaces and self-hosted experiments

---

## Project Status

Chorus is currently an **early MVP / personal dogfooding project**.

The current goal is not to be a polished SaaS product yet.  
The goal is to build a practical local workspace for coordinating multiple AI agents and AI-assisted development workflows.

Expect active changes in:

- routing design
- agent execution model
- CLI integration
- preset format
- task management
- UI/UX
- documentation

---

## Tech Stack

### Client

- **Flutter**
- Dart
- Web / desktop / mobile capable architecture

### Server

- **FastAPI**
- Python
- WebSocket
- JWT authentication
- SQLite / MySQL / PostgreSQL compatible configuration

---

## Repository Structure

```text
Chorus/
├── client/                 # Flutter client
│   └── lib/                # Flutter source code
├── server/                 # FastAPI backend
│   ├── routers/            # API routes
│   ├── schemas/            # Pydantic schemas
│   ├── modules/            # Core application logic
│   ├── util/               # Utility functions
│   ├── app.py              # FastAPI app entry point
│   └── dev.py              # Development server entry point
├── docs/
│   └── assets/             # README images and documentation assets
├── LICENSE
└── README.md
```

---

## Getting Started

### Prerequisites

- Python 3.8+
- Flutter SDK
- Git

---

## Server Setup

Install Python dependencies:

```bash
pip install -r server/requirements.txt
```

Copy the sample environment file:

```bash
cp server/.env.sample server/.env
```

Example development configuration:

```env
ALLOWED_ORIGIN=http://localhost:3000
SECRET_KEY=your-secret-key-here
ACCESS_TOKEN_EXPIRE_MINUTES=30
CONTEXT=development

DB_TYPE=sqlite
DB_PATH=./chorus.db
```

Initialize the development database if needed:

```bash
python server/startup.py
```

Start the development server:

```bash
python server/dev.py
```

Or run with Uvicorn directly:

```bash
uvicorn server.app:app --host 0.0.0.0 --port 8000
```

The API server will be available at:

```text
http://localhost:8000
```

---

## Create a Development User

Create a default development user:

```bash
python server/create_dev_user.py
```

Default account:

```text
Email: dev1@chorus.local
Password: devpass123
```

Create multiple users:

```bash
python server/create_dev_user.py --count 5
```

List development users:

```bash
python server/create_dev_user.py --list
```

Delete a development user:

```bash
python server/create_dev_user.py --delete dev1@chorus.local
```

---

## Client Setup

Install Flutter dependencies:

```bash
cd client
flutter pub get
```

Run the Flutter web client:

```bash
flutter run -d chrome --dart-define=CHORUS_API_BASE_URL=http://localhost:8000/chorus
```

Run on other platforms:

```bash
flutter run -d windows
flutter run -d ios
flutter run -d android
```

> The default API base URL is `http://localhost:8000/chorus`.  
> Adjust `CHORUS_API_BASE_URL` if your server is running elsewhere.

---

## Main API Areas

### Authentication

```text
POST /auth/register
POST /auth/login
POST /auth/logout
POST /token/refresh
```

### Chat

```text
WS   /ws
GET  /chat
POST /chat
```

### Agent

```text
GET  /agent
POST /agent
```

### Routing

```text
GET  /routing
POST /routing
```

### Settings

```text
GET /settings
PUT /settings
```

---

## Configuration

See `server/.env.sample` for the complete environment configuration.

Common variables:

| Variable | Description | Default |
|---|---|---|
| `ALLOWED_ORIGIN` | CORS allowed origin | `*` |
| `SECRET_KEY` | JWT secret key | `your-secret-key-here` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Access token lifetime | `30` |
| `CONTEXT` | Application context path | `/chorus` |
| `DB_TYPE` | Database type: `sqlite`, `mysql`, `postgres` | `sqlite` |
| `DB_PATH` | SQLite database path | `chorus.db` |
| `DB_HOST` | MySQL/PostgreSQL host | `127.0.0.1` |
| `DB_PORT` | MySQL/PostgreSQL port | `0` |
| `DB_USER` | Database user | |
| `DB_PASSWORD` | Database password | |
| `DB_DATABASE` | Database name | |
| `DB_SCHEMA` | Database schema | |
| `RATE_LIMIT_DEFAULT` | Default rate limit | `100/hour` |
| `RATE_LIMIT_LOGIN` | Login rate limit | `5/minute` |
| `RATE_LIMIT_UPLOAD` | Upload rate limit | `120/minute` |
| `RATE_LIMIT_DOWNLOAD` | Download rate limit | `120/minute` |
| `REDIS_HOST` | Redis host | `localhost` |
| `REDIS_PORT` | Redis port | `6379` |
| `REDIS_DB` | Redis DB number | `0` |

---

## Roadmap

Planned or experimental areas:

- CLI adapter support
- model/provider routing rules
- room-level agent assignment
- persistent prompt presets
- task execution history
- file-aware agent workflows
- local automation hooks
- better desktop packaging
- release builds

---

## Design Direction

Chorus is not intended to be just another chatbot UI.

The long-term direction is:

```text
chat rooms
+ agents
+ presets
+ model routing
+ local execution
+ task history
= a practical AI workbench for developers
```

The focus is on workflows where multiple AI tools need to cooperate, while the user keeps control of context, prompts, files, and task boundaries.

---

## Contributing

Issues, suggestions, and pull requests are welcome.

Since Chorus is still early, large architectural changes may happen frequently.  
If you want to contribute, opening an issue first is recommended.

---

## License

This project is licensed under the MIT License.

See [LICENSE](LICENSE) for details.

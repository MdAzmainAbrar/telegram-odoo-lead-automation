# Telegram–Odoo Lead Automation (Self-Hosted, Free Stack)

A self-hosted automation system where a customer messages a Telegram bot, a local AI (Ollama) has a natural conversation with them, qualifies them as a lead, and automatically creates/updates the lead in Odoo CRM — with no paid APIs anywhere in the pipeline.

> **Note on scope change:** the original brief specified WhatsApp Cloud API. This implementation uses **Telegram** instead, for a faster, fully free setup with no business verification requirements. All AI logic, lead-qualification rules, and Odoo integration follow the original brief's design.

---

## Architecture

```
Customer sends Telegram message
        ↓
n8n Telegram Trigger (webhook via Cloudflare Tunnel)
        ↓
Postgres — load recent conversation history
        ↓
Code node — build system prompt + message array
        ↓
Ollama (gemma3:4b) — generate reply as structured JSON
        ↓
Code node — parse JSON, fallback on invalid response
        ↓
Postgres — save user + assistant messages
        ↓
Telegram — send reply back to customer
        ↓
Odoo — authenticate, then create CRM lead
```

All services run in Docker containers on a single local machine (Pop!_OS). Public webhook access is provided via a Cloudflare Quick Tunnel.

---

## Tech Stack

| Component | Tool | Notes |
|---|---|---|
| Automation | n8n Community Edition | Self-hosted via Docker |
| Local AI | Ollama, running `gemma3:4b` | No cloud AI API used |
| CRM | Odoo Community Edition 17.0 | Self-hosted via Docker |
| Database | PostgreSQL 15 | Shared instance, separate databases for n8n / Odoo / app data |
| Messaging | Telegram Bot API | Free, no business verification required |
| Public webhook | Cloudflare Quick Tunnel | Free tier — see limitations below |
| Containerization | Docker + Docker Compose | |

---

## What's Working ✅

- **Telegram bot receives messages** in real time via n8n webhook (through Cloudflare Tunnel)
- **Local AI conversation** — Ollama (`gemma3:4b`) generates contextual replies with no external AI API
- **Structured JSON output** — AI reliably returns `reply`, `lead_ready`, `human_handoff`, `lead_score`, and a structured `lead` object (name, phone, email, company, product interest, requirement, budget, timeline, location) as forced by Ollama's `"format": "json"` option
- **Conversation memory** — prior messages are loaded from Postgres and fed back into the AI's context, so it mostly avoids re-asking for information already provided
- **Invalid-JSON fallback** — if Ollama returns malformed JSON, a safe fallback message is used instead of crashing the workflow
- **Automatic Odoo CRM lead creation** — captured lead data (name, phone, email, company, requirement, budget, timeline, location) is written into a real `crm.lead` record via Odoo's JSON-RPC API
- **Full stack survives a restart** — `docker compose down && up -d` brings all four services back up healthy, confirmed via testing
- **n8n workflow is version-published and exportable** — see `n8n-workflows/Telegram-Odoo-Lead-Bot.json`

---

## Known Limitations / Not Yet Implemented ⚠️

- **No lead deduplication.** Every conversation currently creates a **new** Odoo lead rather than searching for an existing lead by phone number and updating it (this was a stated requirement in the original brief, Section 10). During testing, this produced multiple duplicate "Telegram Lead - {chat_id}" cards for the same test customer.
- **AI language consistency is imperfect.** `gemma3:4b` is a small (4B parameter) local model. In short, single-language exchanges it performs well; in longer bilingual (Bangla/English) conversations it sometimes mixes languages or produces transliterated text instead of proper Bangla script. A larger local model (e.g. `gemma3:12b` or `qwen3:8b`) would likely improve this, at the cost of needing more RAM/compute.
- **`human_handoff` is detected but not acted on.** The AI correctly sets `human_handoff: true` in its JSON output when appropriate (customer requests a human, complains, etc.), but no workflow step currently does anything with that flag (e.g., notify a salesperson, tag the lead differently).
- **No duplicate-message protection.** The brief's suggested `processed_messages` table (to guard against Telegram resending the same webhook event) was not implemented due to time constraints.
- **No business knowledge base.** Company info, FAQs, pricing, and policies are not yet fed into the AI's system prompt — it currently operates on general instructions only, not actual business-specific facts.
- **Cloudflare Quick Tunnel limitation (expected, documented in original brief).** The free tunnel generates a new random URL every time it's restarted. This means `WEBHOOK_URL` in `.env` must be manually updated and the stack restarted each time the tunnel reconnects. A named Cloudflare Tunnel (still free, requires a Cloudflare account) would solve this permanently but was not set up in this phase.
- **Credentials were briefly hardcoded during rapid development.** Odoo admin credentials were temporarily placed directly in HTTP Request node bodies rather than n8n's credential system or environment variables, in order to meet a time constraint. These have been **redacted from the exported workflow JSON** before this repo was made public. The live n8n instance should be updated to use `{{ $env.ODOO_ADMIN_EMAIL }}` / `{{ $env.ODOO_ADMIN_PASSWORD }}` expressions instead, and the real Odoo password should be rotated.

---

## Setup Instructions

### 1. Prerequisites
- Docker + Docker Compose installed
- A Telegram account (to create a bot via [@BotFather](https://t.me/BotFather))
- `cloudflared` installed for the public webhook tunnel

### 2. Clone and configure
```bash
git clone https://github.com/MdAzmainAbrar/telegram-odoo-lead-automation.git
cd telegram-odoo-lead-automation
cp .env.example .env
nano .env   # fill in your own passwords, bot token, etc.
```

**Do not reuse the example passwords.** Also avoid special characters like `$`, `#`, backticks, or quotes in any password value — Docker Compose's `.env` parser treats these specially and can silently corrupt the value.

### 3. Start the stack
```bash
docker compose up -d
docker compose ps   # confirm all 4 containers are healthy
```

### 4. Pull the AI model
```bash
docker exec -it wa_ollama ollama pull gemma3:4b
```

### 5. Start the public tunnel
```bash
cloudflared tunnel --url http://localhost:5678
```
Copy the generated `https://....trycloudflare.com` URL.

### 6. Update the webhook URL
Add the tunnel URL to `.env` as `WEBHOOK_URL=<your-tunnel-url>/`, then:
```bash
docker compose down
docker compose up -d
```

### 7. Complete first-run setup
- n8n: open the tunnel URL, create an owner account
- Odoo: open `localhost:8069`, set a master password, create a CRM database

### 8. Import the workflow
In n8n: **Workflows → Import from File** → select `n8n-workflows/Telegram-Odoo-Lead-Bot.json`. You will need to reconnect the Telegram and Postgres credentials manually (these are not included in the export for security).

### 9. Restart the tunnel each session
Because the free Cloudflare Quick Tunnel URL changes on every restart, steps 5–6 need to be repeated each time you resume development.

---

## Database Schema

```sql
CREATE TABLE conversations (
  id SERIAL PRIMARY KEY,
  chat_id BIGINT NOT NULL,
  role VARCHAR(20) NOT NULL,       -- 'user' or 'assistant'
  content TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
```

---

## Suggested Next Steps

1. Implement lead deduplication (search `crm.lead` by phone before creating)
2. Move Odoo credentials into n8n's credential store / environment variables (partially done — see limitations)
3. Wire up `human_handoff` to actually notify a salesperson or tag the lead
4. Add a `processed_messages` table to guard against duplicate Telegram webhook deliveries
5. Feed real business information (FAQs, pricing, hours) into the AI's system prompt
6. Evaluate a larger local model if language consistency remains an issue
7. Replace the Cloudflare Quick Tunnel with a named tunnel for a stable webhook URL

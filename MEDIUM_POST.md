# Build a Mobile API Backend with GCP Cloud Endpoints and App Engine

So you want to build a backend for your mobile app? You could spin up a VM and manage everything yourself, but honestly, that's a lot of work. Let me show you a simpler way using Google Cloud.

In this tutorial, we'll build a REST API that's ready for production. It has authentication, rate limiting, auto-scaling, and a real database. The best part? It costs almost nothing to run.

**What we're building:**
- A Flask API running on App Engine
- Cloud Endpoints for API management (auth + rate limiting)
- Firestore as our database
- Automatic scaling from 0 to N instances

### Why App Engine?

App Engine is Google's fully managed serverless platform. You deploy your code and Google handles the rest - servers, load balancing, auto-scaling, SSL certificates. It supports Python, Java, Node.js, Go, and more.

The Standard environment (which we're using) scales to zero when there's no traffic, so you only pay when your API is actually being used. It also starts up fast - typically under a second for Python apps.

### Why Firestore?

Firestore is a NoSQL document database built for automatic scaling and high performance. Each document is stored as a set of key-value pairs, and documents are organized into collections.

Key features we're using:
- **Strong consistency** - reads always return the most recent data
- **Real-time listeners** - useful if you want to add live updates later
- **Offline support** - the mobile SDKs can cache data locally
- **Automatic scaling** - handles millions of concurrent users without configuration

This takes about 45 minutes. Let's go.

---

## The Architecture

Before we start, here's what we're building:

![Architecture diagram showing the flow from mobile client through Cloud Endpoints to App Engine and Firestore]

<!-- SCREENSHOT: Add architecture diagram here -->

The request flow is simple:
1. Your app sends a request with an API key
2. Cloud Endpoints validates the key and checks rate limits
3. If everything's good, it forwards to App Engine
4. Flask handles the request and talks to Firestore
5. Response goes back to your app

---

## What You Need

Before starting, make sure you have:
- A GCP account (free tier works fine)
- `gcloud` CLI installed on your machine. Get it here: https://cloud.google.com/sdk/docs/install
  Or use Cloud Shell directly from your browser
- Python 3.12 or newer

---

## Step 1: Clone and Setup

First, grab the code:

```bash
git clone https://github.com/misskecupbung/gcp-cloud-endpoints-mobile-api.git
cd gcp-cloud-endpoints-mobile-api
```

Set your project ID:

```bash
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Verify it's set correctly:

gcloud config get-value project
```

Now run the setup script. This enables all the APIs we need:

```bash
./scripts/setup.sh
```

<!-- SCREENSHOT: Terminal output showing APIs being enabled -->

The script does a few things:
- Enables App Engine, Firestore, Endpoints, and other APIs
- Creates an App Engine app if you don't have one
- Sets up Firestore in native mode
- Updates the OpenAPI spec with your project ID

If it asks you to pick a region, I usually go with `us-central` unless you have a reason to pick something else.

---

## Step 2: Look at the Code

Let's see what we're deploying. Open `app/main.py`:

<!-- SCREENSHOT: VS Code or your editor showing main.py -->

The API has these endpoints:

| Method | Endpoint | What it does |
|--------|----------|--------------|
| GET | /api/v1/health | Health check |
| GET | /api/v1/users | List all users |
| POST | /api/v1/users | Create a user |
| GET | /api/v1/users/{id} | Get one user |
| PUT | /api/v1/users/{id} | Update a user |
| DELETE | /api/v1/users/{id} | Delete a user |

The health endpoint is public. Everything else needs an API key.

This setup uses Firestore instead of in-memory storage, so your data persists across deployments and instance restarts. The health check pings the database to verify connectivity - useful for load balancer health checks and monitoring alerts.

### How Firestore Works in the Code

The app uses the `google-cloud-firestore` Python client. Here's what happens when you create a user:

```python
db = firestore.Client()
doc_ref = db.collection("users").add(user_data)
```

Firestore automatically:
- Generates a unique document ID
- Indexes all fields for querying
- Replicates data across multiple zones for durability

For queries, we can filter and order:

```python
query = db.collection("users").order_by("created_at", direction=firestore.Query.DESCENDING)
```

No need to set up indexes manually for simple queries - Firestore creates single-field indexes automatically.

---

## Step 3: Configure the OpenAPI Spec

Cloud Endpoints uses an OpenAPI spec to know how to handle requests. We need to update it with your project ID:

```bash
sed -i "s/YOUR_PROJECT_ID/$(gcloud config get-value project)/g" openapi.yaml
```

Take a look at `openapi.yaml`. The interesting parts:

**API Key authentication:**
```yaml
securityDefinitions:
  api_key:
    type: "apiKey"
    name: "key"
    in: "query"
```

**Rate limiting:**
```yaml
x-google-management:
  quota:
    limits:
      - name: "read-limit"
        metric: "read-requests"
        unit: "1/min/{project}"
        values:
          STANDARD: 1000
```

This gives each API key 1000 read requests and 100 write requests per minute. You can change these numbers based on your needs.

---

## Step 4: Deploy

Now let's deploy everything:

```bash
./scripts/deploy.sh
```

<!-- SCREENSHOT: Terminal showing deployment progress -->

This script:
1. Creates `app.yaml` from the template
2. Deploys the OpenAPI spec to Cloud Endpoints
3. Deploys the Flask app to App Engine
4. Creates an API key for testing

The first deploy takes a few minutes. Go grab a coffee.

<!-- SCREENSHOT: Cloud Console showing App Engine dashboard with the deployed service -->

When it's done, you'll see your API URL: `https://YOUR_PROJECT_ID.appspot.com`

---

## Step 5: Test Your API

Let's make sure everything works. Run the test script:

```bash
./scripts/test-api.sh
```

<!-- SCREENSHOT: Terminal showing successful API tests -->

Or test manually. First, get your API key:

```bash
export API_HOST="https://$PROJECT_ID.appspot.com"
export API_KEY=$(gcloud services api-keys list --format="value(name)" | head -1 | xargs gcloud services api-keys get-key-string --format="value(keyString)")
```

Try the health check (no auth needed):

```bash
curl "$API_HOST/api/v1/health"
```

You should see something like:

```json
{
  "status": "healthy",
  "service": "mobile-api",
  "database": "connected"
}
```

Now create a user:

```bash
curl -X POST "$API_HOST/api/v1/users?key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "John", "email": "john@example.com"}'
```

<!-- SCREENSHOT: Terminal showing the create user response -->

And list users:

```bash
curl "$API_HOST/api/v1/users?key=$API_KEY"
```

Nice. Your API is live.

---

## Step 6: Check the Monitoring

Go to Cloud Console > Endpoints:

https://console.cloud.google.com/endpoints

<!-- SCREENSHOT: Cloud Endpoints dashboard showing request metrics -->

Here you can see:
- Request counts
- Latency (how fast your API responds)
- Error rates
- Which endpoints are getting hit the most

Click on your service to see more details.

<!-- SCREENSHOT: Detailed view of an endpoint showing latency distribution -->

You can also check logs in Cloud Logging. The app uses structured logging, so you can filter by request type, status code, etc.

---

## Step 7: Test Rate Limiting

Let's make sure rate limiting works:

```bash
./scripts/test-rate-limit.sh
```

<!-- SCREENSHOT: Terminal showing rate limit test with 429 errors -->

This script hammers your API with requests. After hitting the limit, you'll start seeing `429 Too Many Requests` errors.

That's Cloud Endpoints doing its job. Your backend is protected from getting overwhelmed.

---

## Cleanup

Done experimenting? Clean up to avoid charges:

```bash
./scripts/cleanup.sh
```

This removes:
- Old App Engine versions
- The API key
- Firestore data

It keeps the App Engine app itself (you can only have one per project anyway).

---

## What's Next?

This setup is good for getting started. For a real production app, you might want to add:

- **Firebase Auth** - Replace API keys with JWT tokens for user auth
- **Cloud Memorystore** - Add Redis caching for faster responses
- **Cloud Monitoring alerts** - Get notified when things break
- **Custom domain** - Use your own domain instead of appspot.com

The code is on GitHub if you want to fork it and add these features:
https://github.com/misskecupbung/gcp-cloud-endpoints-mobile-api

---

## Wrapping Up

We built a mobile API backend that:
- Scales automatically (even to zero when idle)
- Has proper authentication with API keys
- Rate limits requests to prevent abuse
- Stores data in Firestore
- Logs everything for debugging

Total cost for light usage? Basically free, thanks to GCP's free tier.

Questions? Drop a comment below or open an issue on GitHub.

---

**Tags:** Google Cloud, API, App Engine, Cloud Endpoints, Firestore, Python, Flask, Mobile Development

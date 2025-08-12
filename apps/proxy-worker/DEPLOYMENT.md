# Cloudflare Workers Deployment Guide for Cyrus Proxy

This guide provides step-by-step instructions for deploying the Cyrus proxy service to Cloudflare Workers.

## Overview

The proxy service is already built for Cloudflare Workers and handles:
- OAuth flow with Linear
- Webhook reception from Linear
- Edge worker registration and management
- Secure token storage using KV namespaces
- Event routing to distributed edge workers

## Prerequisites

1. **Cloudflare Account**: Sign up at [cloudflare.com](https://cloudflare.com)
2. **Node.js and pnpm**: Ensure you have Node.js 18+ and pnpm installed
3. **Linear OAuth App**: Create an OAuth application in Linear
4. **Wrangler CLI**: Installed via the project dependencies

## Step 1: Install Dependencies

From the proxy-worker directory:

```bash
cd apps/proxy-worker
pnpm install
```

## Step 2: Configure Linear OAuth Application

1. Go to [Linear Settings > API > OAuth applications](https://linear.app/settings/api)
2. Create a new OAuth application with:
   - **Application name**: Cyrus Agent (or your preferred name)
   - **Description**: AI-powered issue automation
   - **Redirect URIs**: 
     - Production: `https://cyrus-proxy.<your-subdomain>.workers.dev/oauth/callback`
     - Development: `http://localhost:8787/oauth/callback`
   - **Webhook URL**: `https://cyrus-proxy.<your-subdomain>.workers.dev/webhook`
3. Save the Client ID and Client Secret

## Step 3: Create KV Namespaces

Create the required KV namespaces for production:

```bash
# Create KV namespaces
wrangler kv namespace create "OAUTH_TOKENS"
wrangler kv namespace create "OAUTH_STATE"
wrangler kv namespace create "EDGE_TOKENS"
wrangler kv namespace create "WORKSPACE_METADATA"

# For preview/staging environment (optional)
wrangler kv namespace create "OAUTH_TOKENS" --preview
wrangler kv namespace create "OAUTH_STATE" --preview
wrangler kv namespace create "EDGE_TOKENS" --preview
wrangler kv namespace create "WORKSPACE_METADATA" --preview
```

After creating each namespace, you'll receive an ID. Update the `wrangler.toml` file with these IDs:

```toml
[[kv_namespaces]]
binding = "OAUTH_TOKENS"
id = "YOUR_OAUTH_TOKENS_ID"
preview_id = "YOUR_OAUTH_TOKENS_PREVIEW_ID"

[[kv_namespaces]]
binding = "OAUTH_STATE"
id = "YOUR_OAUTH_STATE_ID"
preview_id = "YOUR_OAUTH_STATE_PREVIEW_ID"

[[kv_namespaces]]
binding = "EDGE_TOKENS"
id = "YOUR_EDGE_TOKENS_ID"
preview_id = "YOUR_EDGE_TOKENS_PREVIEW_ID"

[[kv_namespaces]]
binding = "WORKSPACE_METADATA"
id = "YOUR_WORKSPACE_METADATA_ID"
preview_id = "YOUR_WORKSPACE_METADATA_PREVIEW_ID"
```

## Step 4: Set Environment Secrets

Set the required secrets using Wrangler:

```bash
# Linear OAuth credentials
wrangler secret put LINEAR_CLIENT_ID
# Enter your Linear OAuth Client ID when prompted

wrangler secret put LINEAR_CLIENT_SECRET
# Enter your Linear OAuth Client Secret when prompted

# Webhook validation secret (generate a strong random string)
wrangler secret put LINEAR_WEBHOOK_SECRET
# Enter a secure random string (e.g., use: openssl rand -hex 32)

# Encryption key for storing tokens (generate a 32-byte key)
wrangler secret put ENCRYPTION_KEY
# Enter a 32-character encryption key (e.g., use: openssl rand -hex 16)
```

## Step 5: Update Configuration

Edit `wrangler.toml` to set your worker name and OAuth redirect URI:

```toml
name = "cyrus-proxy"  # Or your preferred name
main = "src/index.ts"
compatibility_date = "2024-09-23"
compatibility_flags = ["nodejs_compat"]

[vars]
OAUTH_REDIRECT_URI = "https://cyrus-proxy.<your-subdomain>.workers.dev/oauth/callback"
```

## Step 6: Local Development Testing

Test the worker locally before deploying:

```bash
# Start local development server
pnpm dev

# The worker will be available at http://localhost:8787
# Test the dashboard by visiting http://localhost:8787 in your browser
```

For local testing with secrets, create a `.dev.vars` file:

```bash
LINEAR_CLIENT_ID=your_client_id
LINEAR_CLIENT_SECRET=your_client_secret
LINEAR_WEBHOOK_SECRET=your_webhook_secret
ENCRYPTION_KEY=your_32_char_encryption_key
```

**Important**: Add `.dev.vars` to your `.gitignore` to avoid committing secrets.

## Step 7: Deploy to Cloudflare Workers

Deploy the worker to production:

```bash
# Deploy to production
pnpm deploy

# Or use wrangler directly
wrangler deploy
```

After deployment, you'll receive your worker URL:
```
https://cyrus-proxy.<your-subdomain>.workers.dev
```

## Step 8: Verify Deployment

1. Visit your worker URL to see the dashboard
2. Test OAuth flow by clicking on `/oauth/authorize`
3. Check worker logs:
   ```bash
   wrangler tail
   ```

## Step 9: Update Linear Webhook URL

Go back to your Linear OAuth application settings and update:
- **Redirect URI**: Your production OAuth callback URL
- **Webhook URL**: Your production webhook endpoint

## Step 10: Configure Edge Workers

Edge workers (CLI instances) should connect to your proxy with:

```typescript
const edgeWorker = new EdgeWorker({
  proxyUrl: 'https://cyrus-proxy.<your-subdomain>.workers.dev',
  workspaceIds: ['workspace-id-1', 'workspace-id-2'],
  webhookUrl: 'https://your-edge-worker-url/webhook'
});
```

## Monitoring and Debugging

### View Real-time Logs
```bash
wrangler tail
```

### Check KV Storage
```bash
# List keys in a namespace
wrangler kv key list --namespace-id=YOUR_NAMESPACE_ID

# Get a specific key value
wrangler kv key get "key-name" --namespace-id=YOUR_NAMESPACE_ID
```

### Worker Analytics
Visit the [Cloudflare Dashboard](https://dash.cloudflare.com) to view:
- Request metrics
- Error rates
- Performance data
- KV operations

## Production Considerations

### Custom Domain (Optional)
To use a custom domain instead of workers.dev:

1. Add a custom domain in Cloudflare Dashboard > Workers & Pages > your-worker > Settings > Domains & Routes
2. Update your OAuth redirect URI and webhook URL in Linear

### Rate Limiting
Consider implementing rate limiting for production:

```typescript
// Add to wrangler.toml
[[unsafe.bindings]]
name = "RATE_LIMITER"
type = "ratelimit"
namespace_id = "1"
simple = { limit = 100, period = 60 }
```

### Webhook Security
The service validates webhooks using the LINEAR_WEBHOOK_SECRET. Ensure this is kept secure and rotate periodically.

### Scaling Considerations
- KV storage has eventual consistency (changes take up to 60 seconds globally)
- Consider using Durable Objects for real-time coordination if needed
- Monitor KV operation costs in high-volume scenarios

## Troubleshooting

### Common Issues

1. **"KV namespace not found"**
   - Ensure KV namespace IDs in wrangler.toml match created namespaces
   - Check you're in the correct Cloudflare account

2. **"Unauthorized" OAuth errors**
   - Verify LINEAR_CLIENT_ID and LINEAR_CLIENT_SECRET are set correctly
   - Check redirect URI matches exactly in Linear settings

3. **Webhook validation failures**
   - Ensure LINEAR_WEBHOOK_SECRET matches between Linear and Workers
   - Check webhook URL is accessible and correct

4. **Encryption errors**
   - ENCRYPTION_KEY must be exactly 32 characters
   - Use the same key for encryption and decryption

### Debug Mode
For detailed debugging, you can add console.log statements and view them with:
```bash
wrangler tail --format pretty
```

## Security Best Practices

1. **Rotate secrets regularly**: Update OAuth client secret and encryption keys periodically
2. **Use webhook validation**: Always validate webhook signatures
3. **Implement rate limiting**: Protect against abuse
4. **Monitor access logs**: Check for unusual patterns
5. **Keep dependencies updated**: Regularly update packages for security patches

## Cost Optimization

- **Workers Free Tier**: 100,000 requests/day
- **KV Free Tier**: 100,000 reads/day, 1,000 writes/day
- **Monitor usage** in Cloudflare Dashboard to avoid unexpected charges
- **Implement caching** where appropriate to reduce KV operations

## Next Steps

After successful deployment:

1. Register edge workers using the `/edge/register` endpoint
2. Configure the Cyrus CLI to use your proxy URL
3. Test the complete flow: OAuth → Webhook → Edge Worker
4. Set up monitoring and alerts for production
5. Document your deployment configuration for your team

## Support

For issues specific to:
- **Cloudflare Workers**: Check [Cloudflare Discord](https://discord.cloudflare.com) or [Community Forums](https://community.cloudflare.com)
- **Linear API**: Refer to [Linear API Documentation](https://developers.linear.app)
- **Cyrus Project**: Open an issue in the GitHub repository
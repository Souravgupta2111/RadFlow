import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const requestData = await req.json()
    
    // Retrieve the OpenRouter API key from Supabase Secrets
    // Set this using: supabase secrets set OPENROUTER_API_KEY=b5aad09a7997744b8827d14fb5b6a77e1be3e701545bf2d1b031656efed720bc
    const apiKey = Deno.env.get('OPENROUTER_API_KEY')
    
    if (!apiKey) {
      throw new Error("Missing OPENROUTER_API_KEY secret")
    }
    
    // Override the model to the one requested by the user
    requestData.model = "deepseek/deepseek-v4-flash-latest"

    // Forward the request to OpenRouter
    const openRouterResponse = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://radflow.app', // OpenRouter requires Referer
        'X-Title': 'Radflow', // OpenRouter title
      },
      body: JSON.stringify(requestData)
    })

    // If streaming, return the readable stream directly
    if (requestData.stream) {
      return new Response(openRouterResponse.body, {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/event-stream',
        },
      })
    }

    // Otherwise, parse and return the JSON
    const data = await openRouterResponse.json()
    
    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})

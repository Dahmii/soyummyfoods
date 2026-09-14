$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$shared = Get-Content (Join-Path $root 'functions/_shared/guestRateLimit.ts') -Raw
$checkout = Get-Content (Join-Path $root 'functions/guest-checkout/index.ts') -Raw
$payment = Get-Content (Join-Path $root 'functions/create-stripe-payment-intent/index.ts') -Raw
$status = Get-Content (Join-Path $root 'functions/guest-order-status/index.ts') -Raw
$webhook = Get-Content (Join-Path $root 'functions/stripe-webhook/index.ts') -Raw

if ($shared -notmatch 'crypto\.subtle\.sign\(\x27HMAC\x27' -or $shared -notmatch 'x-forwarded-for') {
  throw 'The shared limiter must derive HMAC keys from X-Forwarded-For.'
}
if ($shared -match 'console\.(warn|error).*clientIp|console\.(warn|error).*forwardedFor') {
  throw 'The shared limiter must not log a raw IP address.'
}
if ($shared -notmatch 'p_ip_key: ipKey' -or $shared -notmatch 'p_attempt_key: attemptKey' -or $shared -match 'p_attempt_key: attemptIdentifier') {
  throw 'The limiter RPC must receive only derived HMAC subject keys.'
}

@(
  @{ Name = 'checkout'; Source = $checkout; Rpc = "client.rpc('create_guest_order'" },
  @{ Name = 'payment'; Source = $payment; Rpc = "client.rpc('prepare_stripe_payment_attempt'" },
  @{ Name = 'status'; Source = $status; Rpc = "client.rpc('get_guest_order_payment_status'" }
) | ForEach-Object {
  $limitPosition = $_.Source.IndexOf('enforceGuestRateLimit(')
  $rpcPosition = $_.Source.IndexOf($_.Rpc)
  if ($limitPosition -lt 0 -or $rpcPosition -lt 0 -or $limitPosition -gt $rpcPosition) {
    throw "The $($_.Name) limiter must run before its privileged RPC."
  }
  if ($_.Source -notmatch "'Retry-After': String\(rateLimit\.retryAfterSeconds\)") {
    throw "The $($_.Name) limiter must return Retry-After on 429."
  }
}

if ($payment.IndexOf('enforceGuestRateLimit(') -gt $payment.IndexOf("stripeRequest('payment_intents'")) {
  throw 'The payment limiter must run before Stripe API calls.'
}
if ($webhook -match 'enforceGuestRateLimit|RATE_LIMIT_HMAC_KEY|consume_guest_rate_limit') {
  throw 'Stripe webhook must remain independent of guest rate limiting.'
}

Write-Output 'Phase 7F Edge static verification passed.'

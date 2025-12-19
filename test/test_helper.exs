# Set up test configuration
Application.put_env(:pin_stripe, :stripe_api_key, "sk_test_123")

Application.put_env(:pin_stripe, :req_options,
  plug: {Req.Test, PinStripe},
  retry: false
)

Logger.configure(level: :warning)
ExUnit.start()

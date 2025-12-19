defmodule PinStripe.Test.MockTest do
  use ExUnit.Case, async: true

  alias PinStripe.Test.Mock
  alias PinStripe.Test.Fixtures
  alias PinStripe.Client

  setup do
    # Config is set globally in test_helper.exs, no need to set or clean up here
    :ok
  end

  describe "delegated response helpers" do
    test "json/2 creates JSON response" do
      Mock.stub(fn conn ->
        Mock.json(conn, %{test: "data"})
      end)

      {:ok, response} = Client.request("/test")
      assert response.body == %{"test" => "data"}
      assert ["application/json; charset=utf-8"] == response.headers["content-type"]
    end

    test "transport_error/2 simulates network error" do
      Mock.stub(fn conn ->
        Mock.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} = Client.request("/test")
    end
  end

  describe "stub/1 with default name" do
    test "stubs with PinStripe as default name" do
      Mock.stub(fn conn ->
        Mock.json(conn, %{id: "cus_123"})
      end)

      {:ok, response} = Client.read("cus_123")
      assert response.body["id"] == "cus_123"
    end

    test "last stub wins for the same request" do
      Mock.stub(fn conn ->
        Mock.json(conn, %{id: "cus_first"})
      end)

      Mock.stub(fn conn ->
        Mock.json(conn, %{id: "cus_second"})
      end)

      {:ok, response} = Client.read("cus_123")
      # Most recent stub is used
      assert response.body["id"] == "cus_second"
    end
  end

  describe "stub/2 with custom name" do
    test "stubs with custom name" do
      # Temporarily change plug name for this test
      Application.put_env(:pin_stripe, :req_options, plug: {Req.Test, :custom_name}, retry: false)

      Mock.stub(
        fn conn ->
          Mock.json(conn, %{id: "test"})
        end,
        :custom_name
      )

      {:ok, response} = Client.request("/test")
      assert response.body["id"] == "test"

      # Restore default plug name
      Application.put_env(:pin_stripe, :req_options, plug: {Req.Test, PinStripe}, retry: false)
    end
  end

  describe "expect/1 with default name" do
    test "expects one request with PinStripe as default" do
      Mock.expect(fn conn ->
        Mock.json(conn, %{id: "cus_123"})
      end)

      {:ok, response} = Client.read("cus_123")
      assert response.body["id"] == "cus_123"
    end
  end

  describe "expect/2 with count and default name" do
    test "expects multiple requests with default name" do
      Mock.expect(
        fn conn ->
          Mock.json(conn, %{id: "cus_test"})
        end,
        2
      )

      {:ok, _} = Client.read("cus_test")
      {:ok, _} = Client.read("cus_test")
    end
  end

  describe "expect/3 with custom name" do
    test "expects requests with custom name and count" do
      # Temporarily change plug name for this test
      Application.put_env(:pin_stripe, :req_options, plug: {Req.Test, :custom}, retry: false)

      Mock.expect(
        fn conn ->
          Mock.json(conn, %{id: "test"})
        end,
        2,
        :custom
      )

      {:ok, _} = Client.request("/test")
      {:ok, _} = Client.request("/test")

      # Restore default plug name
      Application.put_env(:pin_stripe, :req_options, plug: {Req.Test, PinStripe}, retry: false)
    end
  end

  describe "stub with raw data" do
    test "stubs reading a customer with inline data" do
      Mock.stub(fn conn ->
        if conn.method == "GET" and conn.request_path == "/v1/customers/cus_123" do
          Mock.json(conn, %{"id" => "cus_123", "email" => "test@example.com"})
        else
          conn
        end
      end)

      {:ok, response} = Client.read("cus_123")
      assert response.body["id"] == "cus_123"
      assert response.body["email"] == "test@example.com"
    end

    test "stubs creating a customer with inline data" do
      Mock.stub(fn conn ->
        if conn.method == "POST" and conn.request_path == "/v1/customers" do
          Mock.json(conn, %{"id" => "cus_new", "email" => "new@example.com"})
        else
          conn
        end
      end)

      {:ok, response} = Client.create(:customers, %{email: "new@example.com"})
      assert response.body["id"] == "cus_new"
      assert response.body["email"] == "new@example.com"
    end

    test "stubs listing customers with inline list data" do
      Mock.stub(fn conn ->
        if conn.method == "GET" and conn.request_path == "/v1/customers" do
          Mock.json(conn, %{
            "object" => "list",
            "data" => [
              %{"id" => "cus_1", "email" => "user1@example.com"},
              %{"id" => "cus_2", "email" => "user2@example.com"}
            ],
            "has_more" => false
          })
        else
          conn
        end
      end)

      {:ok, response} = Client.read(:customers)
      assert response.body["object"] == "list"
      assert length(response.body["data"]) == 2
      assert hd(response.body["data"])["id"] == "cus_1"
    end

    test "stubs error response with inline data" do
      Mock.stub(fn conn ->
        if conn.method == "GET" and conn.request_path == "/v1/customers/cus_nonexistent" do
          conn
          |> Plug.Conn.put_status(404)
          |> Mock.json(%{
            "error" => %{
              "type" => "invalid_request_error",
              "code" => "resource_missing",
              "message" => "No such customer"
            }
          })
        else
          conn
        end
      end)

      assert {:error, response} = Client.read("cus_nonexistent")
      assert response.status == 404
      assert response.body["error"]["code"] == "resource_missing"
    end
  end

  describe "stub with fixtures" do
    test "stubs reading a customer using fixture" do
      Mock.stub(fn conn ->
        if conn.method == "GET" and conn.request_path == "/v1/customers/cus_123" do
          customer = Fixtures.load(:customer)
          Mock.json(conn, customer)
        else
          conn
        end
      end)

      {:ok, response} = Client.read("cus_123")
      assert response.body["object"] == "customer"
      assert is_binary(response.body["id"])
    end

    test "stubs reading a customer with custom fixture data" do
      # Load fixture once outside the stub
      customer = Fixtures.load(:customer)

      Mock.stub(fn conn ->
        if conn.method == "GET" and conn.request_path == "/v1/customers/cus_123" do
          # Override specific fields for this test
          custom_customer =
            Map.merge(customer, %{"email" => "custom@example.com", "name" => "Custom Name"})

          Mock.json(conn, custom_customer)
        else
          conn
        end
      end)

      {:ok, response} = Client.read("cus_123")
      assert response.body["object"] == "customer"
      assert response.body["email"] == "custom@example.com"
      assert response.body["name"] == "Custom Name"
    end

    test "stubs error response using fixture" do
      Mock.stub(fn conn ->
        if conn.method == "POST" and conn.request_path == "/v1/customers" do
          error = Fixtures.load(:error_400)

          conn
          |> Plug.Conn.put_status(400)
          |> Mock.json(error)
        else
          conn
        end
      end)

      {:error, response} = Client.create(:customers, %{})
      assert response.status == 400
      assert response.body["error"]["code"] == "parameter_invalid_empty"
    end

    test "stubs payment intent using fixture" do
      payment_intent = Fixtures.load(:payment_intent)

      Mock.stub(fn conn ->
        if conn.method == "GET" and String.contains?(conn.request_path, "/payment_intents/") do
          Mock.json(conn, payment_intent)
        else
          conn
        end
      end)

      # Use a custom path since payment_intents don't have auto ID parsing
      {:ok, response} = Client.request("/payment_intents/pi_123")
      assert response.body["object"] == "payment_intent"
    end
  end

  describe "stub with pattern matching" do
    test "handles multiple operations in one stub" do
      Mock.stub(fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/v1/customers/" <> id} ->
            Mock.json(conn, %{"id" => id, "email" => "#{id}@example.com"})

          {"POST", "/v1/customers"} ->
            Mock.json(conn, %{"id" => "cus_new", "email" => "new@example.com"})

          {"DELETE", "/v1/customers/" <> id} ->
            Mock.json(conn, %{"id" => id, "deleted" => true, "object" => "customer"})

          _ ->
            conn
        end
      end)

      {:ok, read_response} = Client.read("cus_123")
      assert read_response.body["id"] == "cus_123"
      assert read_response.body["email"] == "cus_123@example.com"

      {:ok, create_response} = Client.create(:customers, %{email: "new@example.com"})
      assert create_response.body["id"] == "cus_new"

      {:ok, delete_response} = Client.delete("cus_123")
      assert delete_response.body["deleted"] == true
    end

    test "matches different resource types" do
      Mock.stub(fn conn ->
        cond do
          conn.method == "GET" and String.contains?(conn.request_path, "/customers/") ->
            [_, id] = String.split(conn.request_path, "/customers/")
            Mock.json(conn, %{"id" => id, "object" => "customer"})

          conn.method == "GET" and String.contains?(conn.request_path, "/products/") ->
            [_, id] = String.split(conn.request_path, "/products/")
            Mock.json(conn, %{"id" => id, "object" => "product"})

          conn.method == "GET" and String.contains?(conn.request_path, "/subscriptions/") ->
            [_, id] = String.split(conn.request_path, "/subscriptions/")
            Mock.json(conn, %{"id" => id, "object" => "subscription"})

          true ->
            conn
        end
      end)

      {:ok, customer} = Client.read("cus_123")
      assert customer.body["object"] == "customer"

      {:ok, product} = Client.read("product_456")
      assert product.body["object"] == "product"

      {:ok, subscription} = Client.read("sub_789")
      assert subscription.body["object"] == "subscription"
    end
  end

  describe "stub_read/2" do
    test "stubs reading a customer by ID with inline data" do
      Mock.stub_read("cus_123", %{"id" => "cus_123", "email" => "test@example.com"})

      {:ok, response} = Client.read("cus_123")
      assert response.body["id"] == "cus_123"
      assert response.body["email"] == "test@example.com"
    end

    test "stubs reading a customer by ID with merged fixture data" do
      # Load fixture and merge with custom data
      customer =
        Fixtures.load(:customer)
        |> Map.merge(%{"email" => "custom@example.com", "name" => "Custom Name"})

      Mock.stub_read("cus_456", customer)

      {:ok, response} = Client.read("cus_456")
      assert response.body["object"] == "customer"
      assert response.body["email"] == "custom@example.com"
      assert response.body["name"] == "Custom Name"
    end

    test "stubs listing customers by entity type" do
      list_data = %{
        "object" => "list",
        "data" => [
          %{"id" => "cus_1", "email" => "user1@example.com"},
          %{"id" => "cus_2", "email" => "user2@example.com"}
        ],
        "has_more" => false
      }

      Mock.stub_read(:customers, list_data)

      {:ok, response} = Client.read(:customers)
      assert response.body["object"] == "list"
      assert length(response.body["data"]) == 2
    end

    test "stubs reading a product by ID" do
      Mock.stub_read("product_abc", %{"id" => "product_abc", "name" => "Widget"})

      {:ok, response} = Client.read("product_abc")
      assert response.body["name"] == "Widget"
    end

    test "stubs reading a subscription by ID" do
      Mock.stub_read("sub_xyz", %{"id" => "sub_xyz", "status" => "active"})

      {:ok, response} = Client.read("sub_xyz")
      assert response.body["status"] == "active"
    end

    test "stubs listing products by entity type" do
      Mock.stub_read(:products, %{
        "object" => "list",
        "data" => [%{"id" => "product_1"}],
        "has_more" => false
      })

      {:ok, response} = Client.read(:products)
      assert response.body["object"] == "list"
    end
  end

  describe "stub_create/2" do
    test "stubs creating a customer" do
      Mock.stub_create(:customers, %{"id" => "cus_new", "email" => "new@example.com"})

      {:ok, response} = Client.create(:customers, %{email: "new@example.com"})
      assert response.body["id"] == "cus_new"
      assert response.body["email"] == "new@example.com"
    end

    test "stubs creating a product" do
      Mock.stub_create(:products, %{"id" => "product_new", "name" => "New Widget"})

      {:ok, response} = Client.create(:products, %{name: "New Widget"})
      assert response.body["name"] == "New Widget"
    end

    test "stubs creating a subscription" do
      Mock.stub_create(:subscriptions, %{"id" => "sub_new", "status" => "active"})

      {:ok, response} = Client.create(:subscriptions, %{customer: "cus_123"})
      assert response.body["status"] == "active"
    end

    test "stubs creating with fixture data" do
      customer = Fixtures.load(:customer)
      Mock.stub_create(:customers, customer)

      {:ok, response} = Client.create(:customers, %{email: "test@example.com"})
      assert response.body["object"] == "customer"
    end
  end

  describe "stub_update/2" do
    test "stubs updating a customer by ID" do
      Mock.stub_update("cus_123", %{"id" => "cus_123", "name" => "Updated Name"})

      {:ok, response} = Client.update("cus_123", %{name: "Updated Name"})
      assert response.body["name"] == "Updated Name"
    end

    test "stubs updating a product by ID" do
      Mock.stub_update("product_abc", %{"id" => "product_abc", "name" => "Updated Widget"})

      {:ok, response} = Client.update("product_abc", %{name: "Updated Widget"})
      assert response.body["name"] == "Updated Widget"
    end

    test "stubs updating a subscription by ID" do
      Mock.stub_update("sub_xyz", %{"id" => "sub_xyz", "status" => "canceled"})

      {:ok, response} = Client.update("sub_xyz", %{status: "canceled"})
      assert response.body["status"] == "canceled"
    end
  end

  describe "stub_delete/2" do
    test "stubs deleting a customer by ID" do
      Mock.stub_delete("cus_123", %{"id" => "cus_123", "deleted" => true, "object" => "customer"})

      {:ok, response} = Client.delete("cus_123")
      assert response.body["deleted"] == true
    end

    test "stubs deleting a product by ID" do
      Mock.stub_delete("product_abc", %{
        "id" => "product_abc",
        "deleted" => true,
        "object" => "product"
      })

      {:ok, response} = Client.delete("product_abc")
      assert response.body["deleted"] == true
    end

    test "stubs deleting a subscription by ID" do
      Mock.stub_delete("sub_xyz", %{
        "id" => "sub_xyz",
        "deleted" => true,
        "object" => "subscription"
      })

      {:ok, response} = Client.delete("sub_xyz")
      assert response.body["deleted"] == true
    end
  end

  describe "stub_error/3" do
    test "stubs a 404 error for a customer ID" do
      Mock.stub_error("cus_nonexistent", 404, %{
        "error" => %{
          "type" => "invalid_request_error",
          "code" => "resource_missing",
          "message" => "No such customer"
        }
      })

      {:error, response} = Client.read("cus_nonexistent")
      assert response.status == 404
      assert response.body["error"]["code"] == "resource_missing"
    end

    test "stubs a 400 error for customer creation" do
      Mock.stub_error(:customers, 400, %{
        "error" => %{
          "type" => "invalid_request_error",
          "code" => "parameter_invalid_empty",
          "message" => "Missing required parameter"
        }
      })

      {:error, response} = Client.create(:customers, %{})
      assert response.status == 400
      assert response.body["error"]["code"] == "parameter_invalid_empty"
    end

    test "stubs error using fixture" do
      error = Fixtures.load(:error_404)
      Mock.stub_error("product_missing", 404, error)

      {:error, response} = Client.read("product_missing")
      assert response.status == 404
      assert response.body["error"]["type"] == "invalid_request_error"
    end

    test "stubs a 401 error for any request" do
      Mock.stub_error(:any, 401, %{
        "error" => %{
          "type" => "invalid_request_error",
          "message" => "Invalid API key"
        }
      })

      {:error, response} = Client.read("cus_123")
      assert response.status == 401
    end
  end
end

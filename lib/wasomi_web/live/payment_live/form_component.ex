defmodule WasomiWeb.PaymentLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.Payments

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage payment records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="payment-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:provider]}
          type="select"
          label="Provider"
          prompt="Choose a value"
          options={Ecto.Enum.values(Wasomi.Payments.Payment, :provider)}
        />
        <.input field={@form[:provider_reference]} type="text" label="Provider reference" />
        <.input field={@form[:amount_minor]} type="number" label="Amount minor" />
        <.input field={@form[:currency]} type="text" label="Currency" />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          prompt="Choose a value"
          options={Ecto.Enum.values(Wasomi.Payments.Payment, :status)}
        />
        <.input field={@form[:paid_at]} type="datetime-local" label="Paid at" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Payment</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{payment: payment} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Payments.change_payment(payment))
     end)}
  end

  @impl true
  def handle_event("validate", %{"payment" => payment_params}, socket) do
    changeset = Payments.change_payment(socket.assigns.payment, payment_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"payment" => payment_params}, socket) do
    save_payment(socket, socket.assigns.action, payment_params)
  end

  defp save_payment(socket, :edit, payment_params) do
    case Payments.update_payment(socket.assigns.payment, payment_params) do
      {:ok, payment} ->
        notify_parent({:saved, payment})

        {:noreply,
         socket
         |> put_flash(:info, "Payment updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_payment(socket, :new, payment_params) do
    case Payments.create_payment(payment_params) do
      {:ok, payment} ->
        notify_parent({:saved, payment})

        {:noreply,
         socket
         |> put_flash(:info, "Payment created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end

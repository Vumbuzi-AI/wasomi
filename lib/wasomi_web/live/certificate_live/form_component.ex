defmodule WasomiWeb.CertificateLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.Certificates

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage certificate records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="certificate-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          prompt="Choose a value"
          options={Ecto.Enum.values(Wasomi.Certificates.Certificate, :type)}
        />
        <.input field={@form[:serial_number]} type="text" label="Serial number" />
        <.input field={@form[:file_key]} type="text" label="File key" />
        <.input field={@form[:issued_at]} type="datetime-local" label="Issued at" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Certificate</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{certificate: certificate} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Certificates.change_certificate(certificate))
     end)}
  end

  @impl true
  def handle_event("validate", %{"certificate" => certificate_params}, socket) do
    changeset = Certificates.change_certificate(socket.assigns.certificate, certificate_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"certificate" => certificate_params}, socket) do
    save_certificate(socket, socket.assigns.action, certificate_params)
  end

  defp save_certificate(socket, :edit, certificate_params) do
    case Certificates.update_certificate(socket.assigns.certificate, certificate_params) do
      {:ok, certificate} ->
        notify_parent({:saved, certificate})

        {:noreply,
         socket
         |> put_flash(:info, "Certificate updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_certificate(socket, :new, certificate_params) do
    case Certificates.create_certificate(certificate_params) do
      {:ok, certificate} ->
        notify_parent({:saved, certificate})

        {:noreply,
         socket
         |> put_flash(:info, "Certificate created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end

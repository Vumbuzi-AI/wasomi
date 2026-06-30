defmodule WasomiWeb.CertificateLive.Index do
  use WasomiWeb, :live_view

  alias Wasomi.Certificates
  alias Wasomi.Certificates.Certificate

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :certificates, Certificates.list_certificates())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Certificate")
    |> assign(:certificate, Certificates.get_certificate!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Certificate")
    |> assign(:certificate, %Certificate{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Certificates")
    |> assign(:certificate, nil)
  end

  @impl true
  def handle_info({WasomiWeb.CertificateLive.FormComponent, {:saved, certificate}}, socket) do
    {:noreply, stream_insert(socket, :certificates, certificate)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    certificate = Certificates.get_certificate!(id)
    {:ok, _} = Certificates.delete_certificate(certificate)

    {:noreply, stream_delete(socket, :certificates, certificate)}
  end
end

# Certificate Generation, Rendering & Delivery

How certificates are built, rendered to PDF, stored and emailed in this Phoenix/LiveView app —
plus an adapted version for a **course-completion certificate** on an e-learning site.

Source files referenced:

- `lib/erp_live_web/live/member_details_live/cert_component.ex` — template + generate event
- `lib/erp_live/signing_helppp.ex` — the clean HTML → PDF renderer (use this one)
- `lib/erp_live/sgmail.ex` — email delivery (Mailjet over Finch)
- `lib/erp_live/certificates/certificate.ex` / `certificates.ex` — Ecto schema + context
- `assets/js/app.js` (`Hooks.download_cert`) — client-side PDF download
- `lib/erp_live/application.ex`, `config/runtime.exs` — renderer bootstrapping

---

## 1. The architecture

There are **two independent paths**, and you want both on an e-learning site:

| Path            | Trigger                      | Tech                                                         | Used for                                                           |
| --------------- | ---------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------ |
| **Server-side** | Admin/system issues the cert | HTML string → `wkhtmltopdf` or headless Chrome → PDF on disk | Archival copy, emailing, public verification URL                   |
| **Client-side** | Learner clicks "Download"    | `html2canvas` snapshot of the rendered DOM → `jsPDF`         | Instant download of exactly what's on screen, no server round-trip |

The single source of truth is **one HTML/CSS certificate design**. The server path feeds it to a
headless browser; the client path screenshots the already-rendered LiveView markup.

---

## 2. Server-side: HTML → PDF

### 2.1 The renderer (the good implementation)

`lib/erp_live/signing_helppp.ex` is the module to copy. It tries `wkhtmltopdf` first, falls back to
headless Chrome, writes the HTML to a temp file, shells out, validates that a non-empty PDF actually
appeared, copies it into `priv/static/uploads/`, and cleans up temp files in an `after` block.

```elixir
defmodule ErpLive.SigningHelppp do
  @doc """
  Converts an HTML string into a PDF and saves it to priv/static/uploads/.
  Returns {:ok, filename} or {:error, reason}.
  """
  def html_to_pdf(html) when is_binary(html) do
    tmp_dir = System.tmp_dir!()
    id = :erlang.unique_integer([:positive])

    html_path      = Path.join(tmp_dir, "terms_#{id}.html")
    tmp_pdf        = Path.join(tmp_dir, "terms_#{id}.pdf")
    chrome_profile = Path.join(tmp_dir, "chrome_pdf_profile_#{id}")

    output_pdf =
      Path.join([:code.priv_dir(:erp_live), "static", "uploads", "signed_#{id}.pdf"])

    case pdf_renderer() do
      nil ->
        {:error,
         "no PDF renderer is available; install wkhtmltopdf, install Chrome, " <>
           "or configure WKHTMLTOPDF_PATH/CHROME_PATH"}

      renderer ->
        try do
          File.write!(html_path, html)

          case render_pdf(renderer, html_path, tmp_pdf, chrome_profile) do
            :ok -> save_pdf(tmp_pdf, output_pdf)
            {:error, reason} -> {:error, reason}
          end
        after
          cleanup([html_path, tmp_pdf])
          File.rm_rf(chrome_profile)
        end
    end
  end

  defp pdf_renderer do
    cond do
      path = wkhtmltopdf_path() -> {:wkhtmltopdf, path}
      path = chrome_path()      -> {:chrome, path}
      true -> nil
    end
  end

  defp render_pdf({:wkhtmltopdf, executable}, html_path, tmp_pdf, _chrome_profile) do
    args = [
      "--enable-local-file-access",
      "--page-size", "A4",
      "--margin-top", "15mm", "--margin-bottom", "15mm",
      "--margin-left", "15mm", "--margin-right", "15mm",
      "--encoding", "utf-8",
      "--quiet",
      html_path, tmp_pdf
    ]

    run_renderer(executable, args, tmp_pdf, "wkhtmltopdf")
  end

  defp render_pdf({:chrome, executable}, html_path, tmp_pdf, chrome_profile) do
    args = [
      "--headless", "--disable-gpu",
      "--disable-background-networking", "--disable-background-mode",
      "--disable-component-update", "--disable-default-apps",
      "--disable-extensions", "--disable-sync",
      "--metrics-recording-only", "--mute-audio",
      "--no-first-run", "--no-default-browser-check",
      "--no-pdf-header-footer",
      "--allow-file-access-from-files",
      "--user-data-dir=#{chrome_profile}",
      "--print-to-pdf=#{tmp_pdf}",
      "file://#{html_path}"
    ]

    run_chrome(executable, args, tmp_pdf)
  end

  defp run_renderer(executable, args, tmp_pdf, renderer_name) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {_output, 0} ->
        if File.regular?(tmp_pdf),
          do: :ok,
          else: {:error, "#{renderer_name} exited successfully but did not create a PDF"}

      {output, code} ->
        {:error, "#{renderer_name} failed (exit #{code}): #{output}"}
    end
  end

  # Chrome doesn't reliably exit after --print-to-pdf, so we watch stdout for
  # "bytes written to file" and hard-cap the wait at 15s.
  defp run_chrome(executable, args, tmp_pdf) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary, :exit_status, :stderr_to_stdout, args: args
      ])

    await_chrome(port, tmp_pdf, System.monotonic_time(:millisecond) + 15_000, "")
  end

  defp await_chrome(port, tmp_pdf, deadline, output) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        output = output <> data

        if String.contains?(output, "bytes written to file") and valid_pdf?(tmp_pdf) do
          close_port(port)
          :ok
        else
          await_chrome(port, tmp_pdf, deadline, output)
        end

      {^port, {:exit_status, 0}} ->
        if valid_pdf?(tmp_pdf),
          do: :ok,
          else: {:error, "Chrome exited successfully but did not create a PDF"}

      {^port, {:exit_status, code}} ->
        {:error, "Chrome failed (exit #{code}): #{output}"}
    after
      remaining ->
        close_port(port)

        if valid_pdf?(tmp_pdf),
          do: :ok,
          else: {:error, "Chrome timed out while generating the PDF: #{output}"}
    end
  end

  defp valid_pdf?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> true
      _ -> false
    end
  end

  defp close_port(port), do: if(Port.info(port), do: Port.close(port))

  defp save_pdf(tmp_pdf, output_pdf) do
    File.cp!(tmp_pdf, output_pdf)
    {:ok, Path.basename(output_pdf)}
  end

  defp wkhtmltopdf_path do
    path =
      Application.get_env(:pdf_generator, :wkhtml_path) ||
        System.find_executable("wkhtmltopdf")

    if is_binary(path) and File.regular?(path), do: path
  end

  defp chrome_path do
    [
      System.get_env("CHROME_PATH"),
      System.find_executable("google-chrome"),
      System.find_executable("google-chrome-stable"),
      System.find_executable("chromium"),
      System.find_executable("chromium-browser"),
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium"
    ]
    |> Enum.find(&(is_binary(&1) and File.regular?(&1)))
  end

  defp cleanup(paths) do
    Enum.each(paths, fn path ->
      if path && File.exists?(path), do: File.rm(path)
    end)
  end
end
```

Call site (`lib/erp_live_web/live/terms_live.ex`) — note it stores only the **basename** on the
record and builds the public URL from it:

```elixir
html = build_signed_html(signer_name, signer_designation, signature, date_str)

case ErpLive.SigningHelppp.html_to_pdf(html) do
  {:ok, signed_doc_filename} ->
    case Accounts.sign_terms(user, signature, signed_doc_filename) do
      {:ok, user} ->
        signed_doc_url = "https://gs1kenya.org/uploads/#{URI.encode(signed_doc_filename)}"
        ErpLive.Accounts.UserNotifier.deliver_signed_terms(user, signed_doc_url)
        {:noreply, socket |> assign(signed: true) |> push_navigate(to: ~p"/company/portal")}

      {:error, _} ->
        {:noreply, assign(socket, error: "Something went wrong saving your signature.")}
    end

  {:error, reason} ->
    {:noreply, assign(socket, error: "Could not process signature: #{reason}")}
end
```

### 2.2 Renderer bootstrapping

`config/runtime.exs`:

```elixir
if wkhtmltopdf_path = System.get_env("WKHTMLTOPDF_PATH") do
  config :pdf_generator, wkhtml_path: wkhtmltopdf_path
end
```

`lib/erp_live/application.ex` — start the PDF app only if the binary is actually present, so a
missing `wkhtmltopdf` degrades to a warning rather than a boot crash:

```elixir
def start(_type, _args) do
  maybe_start_pdf_generator()
  children = [...]
  Supervisor.start_link(children, strategy: :one_for_one, name: ErpLive.Supervisor)
end

defp maybe_start_pdf_generator do
  case wkhtmltopdf_path() do
    path when is_binary(path) ->
      case Application.ensure_all_started(:pdf_generator) do
        {:ok, _apps} -> :ok
        {:error, reason} -> Logger.warning("PDF generator could not be started: #{inspect(reason)}")
      end

    nil ->
      Logger.warning(
        "wkhtmltopdf-based PDF export is disabled because wkhtmltopdf is unavailable; " <>
          "install it or set WKHTMLTOPDF_PATH"
      )
  end
end
```

`mix.exs`:

```elixir
{:pdf_generator, "~> 0.6.0"},
{:pdf2htmlex, "~> 0.2.0"},
```

### 2.3 The older `PdfGenerator` path (and what's wrong with it)

`cert_component.ex` builds three documents (membership certificate, annual license, letter of
authenticity) as interpolated HTML strings and renders each with the `pdf_generator` package:

```elixir
def handle_event("generate_cert", %{"member" => member_params}, socket) do
  member = Members.get_member!(member_params["members"])

  # QR code for verification
  qrcode = :qrcode.encode(member_params["serial"])
  png    = :qrcode_demo.simple_png_encode(qrcode)
  :file.write_file(~p"/uploads/documents/" <> member_params["serial"] <> ".png", png)

  html  = "...membership certificate HTML..."
  html2 = "...annual license HTML..."
  html3 = "...letter of authenticity HTML..."

  file_name = PdfGenerator.generate!(html,  page_size: "A4", filename: "1" <> member_params["members"])
  file_n    = PdfGenerator.generate!(html2, page_size: "A1", filename: "2" <> member_params["members"])
  file_nm   = PdfGenerator.generate!(html3, page_size: "A4", filename: "3" <> member_params["members"])

  File.rename(file_name, "/home/joss/elixir/erp_live/priv/static/uploads/membership_certificate#{member_params["members"]}.pdf")
  # ...
end
```

**Do not copy this part.** Known problems, all worth avoiding in the new app:

1. **Hardcoded absolute path** `/home/joss/elixir/erp_live/...` — breaks on any other machine. Use
   `Path.join([:code.priv_dir(:my_app), "static", "uploads", ...])`.
2. **`~p"..."` used for filesystem paths** — `~p` is Phoenix's _verified route_ sigil. It produces a
   URL path, not a disk path, and only validates against the router. Wrong tool.
3. **`File.rename/2` across filesystems** — the tmp dir and `priv/static` are often different mounts,
   where `rename` fails with `:exdev`. `File.cp!/2` then `File.rm/1` is safe.
4. **Return values ignored** — `File.rename` and `File.stream!` results are bound but never matched,
   so a failed write still reports "Certificates Generated successfully".
5. **`cond do member -> ...` with dead code** — `{:ok, member}` on its own line is discarded; the
   `true ->` error branch is unreachable because `member` came from `get_member!` (which raises).
6. **Design as an interpolated string** duplicated from the HEEx template — the two drift apart. Keep
   one `.html.heex` and render it to a string (see §4.3).

### 2.4 The design itself

`cert_component.ex:40-175` holds the visual design as inline-styled HEEx. Inline styles are
deliberate: **`wkhtmltopdf` and `html2canvas` both handle inline `style` attributes far more
reliably than external stylesheets or Tailwind classes**, and `html2canvas` in particular ignores a
lot of modern CSS. Notable techniques:

- Fixed pixel dimensions (`width: 1400px`) rather than responsive units, so the PDF is deterministic.
- Absolute `https://` image URLs for logo/seal/signatures — no relative asset paths.
- Brand colour as a literal hex (`#F26334`), repeated inline.
- `<p style="background-color: #000000;height: 2px;width: 100%;">` as horizontal rules — more
  portable across renderers than `<hr>` or `border-bottom`.

---

## 3. Client-side: instant download

`assets/js/app.js` (`Hooks.download_cert`). The button carries `phx-hook="download_cert"` and an id
of the form `cert-download-<id>`; the certificate markup lives in `cert-only-<id>`.

```javascript
Hooks.download_cert = {
  mounted() {
    const elementId = this.el.id; // "cert-download-5"
    const memberId = elementId.replace("cert-download-", "");

    this.el.addEventListener("click", () => {
      const invoiceContainer = document.getElementById("cert-only-" + memberId);
      if (!invoiceContainer) {
        console.error(
          "download_cert: container not found for",
          "cert-only-" + memberId,
        );
        return;
      }
      if (typeof html2canvas === "undefined") {
        console.error("download_cert: html2canvas is not loaded on this page");
        return;
      }
      if (!window.jspdf) {
        console.error(
          "download_cert: jsPDF (window.jspdf) is not loaded on this page",
        );
        return;
      }

      // Wait for every image (logo, seal, signatures) to settle, or the canvas
      // snapshot captures empty boxes.
      const images = invoiceContainer.querySelectorAll("img");
      const waitForImages = Promise.all(
        Array.from(images).map((img) =>
          img.complete
            ? Promise.resolve()
            : new Promise((res) => {
                img.onload = res;
                img.onerror = res;
              }),
        ),
      );

      waitForImages.then(() => {
        html2canvas(invoiceContainer, {
          useCORS: true,
          allowTaint: false,
          scale: 2, // 2x for print sharpness
          width: invoiceContainer.scrollWidth,
          height: invoiceContainer.scrollHeight,
          windowWidth: invoiceContainer.scrollWidth,
          windowHeight: invoiceContainer.scrollHeight,
        })
          .then((canvas) => {
            const imgData = canvas.toDataURL("image/png");
            const { jsPDF } = window.jspdf;
            const pdf = new jsPDF("l", "mm", "a4"); // landscape A4

            const pdfWidth = pdf.internal.pageSize.getWidth();
            const pdfHeight = pdf.internal.pageSize.getHeight();
            const imgProps = pdf.getImageProperties(imgData);
            const imgRatio = imgProps.width / imgProps.height;
            const pdfRatio = pdfWidth / pdfHeight;

            // Fit-inside (contain) + centre, so nothing is cropped or stretched.
            let renderWidth, renderHeight;
            if (imgRatio > pdfRatio) {
              renderWidth = pdfWidth;
              renderHeight = pdfWidth / imgRatio;
            } else {
              renderHeight = pdfHeight;
              renderWidth = pdfHeight * imgRatio;
            }
            const xOffset = (pdfWidth - renderWidth) / 2;
            const yOffset = (pdfHeight - renderHeight) / 2;

            pdf.addImage(
              imgData,
              "PNG",
              xOffset,
              yOffset,
              renderWidth,
              renderHeight,
            );
            pdf.save("certificate.pdf");
          })
          .catch((err) => console.error("download_cert failed:", err));
      });
    });
  },
};
```

Required in the layout (`lib/erp_live_web/components/layouts/accounts.html.heex:620-621`):

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
```

jsPDF 2.x exposes `window.jspdf.jsPDF` (the `umd` build). jsPDF 1.x exposed a bare `window.jsPDF` —
some layouts in this repo still load 1.5.1, which is why the hook guards on `window.jspdf`.

Trade-off to know: `html2canvas` rasterises, so the PDF contains **an image, not selectable text**.
Fine for a certificate; bad if you need text search or accessibility. The server-side path produces
real text.

---

## 4. Adapting this to an e-learning site

### 4.1 Schema

The existing schema (`lib/erp_live/certificates/certificate.ex`) is minimal — a file path, a name, a
status, and a `code` used as the public lookup key:

```elixir
schema "certificates" do
  field :certificate_file, :string
  field :certificate_name, :string
  field :description, :string
  field :status, :string
  field :code, :string
  belongs_to :member, Member, foreign_key: :member_id

  timestamps()
end
```

For an e-learning site, extend it to carry what has to appear on the certificate and what verifies it:

```elixir
defmodule Learning.Certificates.Certificate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "certificates" do
    field :serial, :string          # public verification code, e.g. "CERT-8F3A-2K9D"
    field :learner_name, :string    # snapshot — must not change if the user renames later
    field :course_title, :string    # snapshot
    field :issued_on, :date
    field :expires_on, :date        # nil = never expires
    field :grade, :string
    field :hours, :decimal          # CPD/CEU credit hours
    field :pdf_file, :string        # basename only, e.g. "certificate_1723.pdf"
    field :status, :string, default: "issued"   # issued | revoked

    belongs_to :user, Learning.Accounts.User
    belongs_to :course, Learning.Courses.Course

    timestamps()
  end

  @fields ~w(serial learner_name course_title issued_on expires_on grade hours
             pdf_file status user_id course_id)a

  def changeset(certificate, attrs) do
    certificate
    |> cast(attrs, @fields)
    |> validate_required([:serial, :learner_name, :course_title, :issued_on, :user_id, :course_id])
    |> unique_constraint(:serial)
    |> unique_constraint([:user_id, :course_id])   # one certificate per enrolment
    |> assoc_constraint(:user)
    |> assoc_constraint(:course)
  end
end
```

Snapshotting `learner_name` / `course_title` matters: a certificate is a historical record. If you
join to `users.name` at render time, editing a profile silently rewrites every past certificate.

Migration:

```elixir
create table(:certificates) do
  add :serial, :string, null: false
  add :learner_name, :string, null: false
  add :course_title, :string, null: false
  add :issued_on, :date, null: false
  add :expires_on, :date
  add :grade, :string
  add :hours, :decimal
  add :pdf_file, :string
  add :status, :string, null: false, default: "issued"
  add :user_id, references(:users, on_delete: :restrict), null: false
  add :course_id, references(:courses, on_delete: :restrict), null: false

  timestamps()
end

create unique_index(:certificates, [:serial])
create unique_index(:certificates, [:user_id, :course_id])
create index(:certificates, [:course_id])
```

### 4.2 Issuing context

Mirrors `ErpLive.Certificates` but adds serial generation, idempotency, and verification lookup:

```elixir
defmodule Learning.Certificates do
  import Ecto.Query, warn: false
  alias Learning.Repo
  alias Learning.Certificates.Certificate

  @doc """
  Issues a certificate for a completed enrolment. Idempotent — returns the
  existing certificate if one was already issued.
  """
  def issue(user, course, attrs \\ %{}) do
    case Repo.get_by(Certificate, user_id: user.id, course_id: course.id) do
      %Certificate{} = existing ->
        {:ok, existing}

      nil ->
        %Certificate{}
        |> Certificate.changeset(
          Map.merge(
            %{
              serial: generate_serial(),
              learner_name: user.name,
              course_title: course.title,
              issued_on: Date.utc_today(),
              user_id: user.id,
              course_id: course.id
            },
            attrs
          )
        )
        |> Repo.insert()
    end
  end

  @doc "Public lookup for /verify/:serial. Only returns non-revoked certificates."
  def get_by_serial(serial) do
    Repo.get_by(Certificate, serial: serial, status: "issued")
    |> Repo.preload([:user, :course])
  end

  def revoke(%Certificate{} = certificate),
    do: update_certificate(certificate, %{status: "revoked"})

  def update_certificate(%Certificate{} = certificate, attrs) do
    certificate |> Certificate.changeset(attrs) |> Repo.update()
  end

  def list_for_user(user_id) do
    Repo.all(
      from c in Certificate,
        where: c.user_id == ^user_id and c.status == "issued",
        order_by: [desc: c.issued_on],
        preload: [:course]
    )
  end

  # 12 chars of Crockford-ish base32, grouped for readability.
  defp generate_serial do
    raw =
      :crypto.strong_rand_bytes(8)
      |> Base.encode32(padding: false)
      |> binary_part(0, 12)

    "CERT-" <> (raw |> String.to_charlist() |> Enum.chunk_every(4) |> Enum.join("-"))
  end
end
```

`generate_serial/0` uses `:crypto.strong_rand_bytes/1`, not a sequential id. A guessable serial lets
anyone enumerate every certificate you've ever issued via the public verify endpoint.

### 4.3 The certificate template — one source of truth

Put the design in a real HEEx component and render it to a string for the PDF path. This is the fix
for the string-duplication problem in §2.3.

`lib/learning_web/components/certificate.ex`:

```elixir
defmodule LearningWeb.Components.Certificate do
  use Phoenix.Component

  attr :cert, :map, required: true
  attr :verify_url, :string, required: true
  attr :qr_data_uri, :string, default: nil

  def certificate(assigns) do
    ~H"""
    <div
      id={"cert-only-#{@cert.id}"}
      style="width: 1400px; height: 990px; padding: 60px; box-sizing: border-box;
             background: #ffffff; font-family: Georgia, 'Times New Roman', serif;
             border: 14px solid #1e3a8a; position: relative;"
    >
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 48px;">
        <img src="https://cdn.example.com/logo.png" alt="logo" style="width: 210px; height: 90px;" />
        <p style="font-size: 1.4rem; font-weight: 600; color: #1e3a8a;">Certificate of Completion</p>
      </div>

      <div style="text-align: center;">
        <p style="font-size: 1.3rem; color: #444; margin-bottom: 8px;">This is to certify that</p>

        <p style="font-size: 3.2rem; font-weight: 800; color: #1e3a8a; margin: 0 0 8px;">
          <%= @cert.learner_name %>
        </p>
        <p style="background-color: #1e3a8a; height: 3px; width: 60%; margin: 0 auto 32px;"></p>

        <p style="font-size: 1.3rem; color: #444; margin-bottom: 8px;">
          has successfully completed the course
        </p>
        <p style="font-size: 2.4rem; font-weight: 700; color: #111; margin: 0 0 40px;">
          <%= @cert.course_title %>
        </p>

        <div style="display: flex; justify-content: center; gap: 80px; margin-bottom: 56px;">
          <div>
            <p style="font-size: 1rem; color: #666; margin: 0;">Issued</p>
            <p style="font-size: 1.4rem; font-weight: 700; color: #111; margin: 0;">
              <%= Calendar.strftime(@cert.issued_on, "%d %B %Y") %>
            </p>
          </div>
          <div :if={@cert.hours}>
            <p style="font-size: 1rem; color: #666; margin: 0;">Credit hours</p>
            <p style="font-size: 1.4rem; font-weight: 700; color: #111; margin: 0;">
              <%= @cert.hours %>
            </p>
          </div>
          <div :if={@cert.grade}>
            <p style="font-size: 1rem; color: #666; margin: 0;">Grade</p>
            <p style="font-size: 1.4rem; font-weight: 700; color: #111; margin: 0;">
              <%= @cert.grade %>
            </p>
          </div>
        </div>
      </div>

      <div style="display: flex; justify-content: space-between; align-items: flex-end;">
        <div style="width: 40%;">
          <img src="https://cdn.example.com/signature.png" alt="signature" style="width: 180px;" />
          <p style="background-color: #000; height: 2px; width: 100%; margin: 4px 0;"></p>
          <p style="font-size: 1.1rem; font-weight: 700; color: #1e3a8a; margin: 0;">
            Programme Director
          </p>
        </div>

        <div style="text-align: center;">
          <img :if={@qr_data_uri} src={@qr_data_uri} alt="verify" style="width: 120px; height: 120px;" />
          <p style="font-size: 0.85rem; color: #666; margin: 6px 0 0;">Verify at</p>
          <p style="font-size: 0.85rem; color: #1e3a8a; margin: 0;"><%= @verify_url %></p>
          <p style="font-size: 0.95rem; font-weight: 700; letter-spacing: 1px; margin: 4px 0 0;">
            <%= @cert.serial %>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
```

Keep the inline styles. Tailwind classes will not survive `wkhtmltopdf` or `html2canvas`.

Render it to a standalone HTML document for the PDF path:

```elixir
defmodule Learning.Certificates.Renderer do
  import Phoenix.Component, only: [assigns_to_attributes: 1]
  alias LearningWeb.Components.Certificate

  def to_html(cert, verify_url, qr_data_uri) do
    inner =
      Certificate.certificate(%{
        cert: cert,
        verify_url: verify_url,
        qr_data_uri: qr_data_uri,
        __changed__: nil
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    """
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Certificate #{cert.serial}</title>
        <style>
          @page { size: A4 landscape; margin: 0; }
          body  { margin: 0; }
        </style>
      </head>
      <body>#{inner}</body>
    </html>
    """
  end
end
```

### 4.4 QR code for verification

The existing code writes a PNG to disk (`:qrcode` + `:qrcode_demo` Erlang libs):

```elixir
qrcode = :qrcode.encode(member_params["serial"])
png    = :qrcode_demo.simple_png_encode(qrcode)
:file.write_file(path, png)
```

Inline it as a data URI instead — no file to manage, and it works identically in both render paths:

```elixir
defp qr_data_uri(verify_url) do
  png =
    verify_url
    |> :qrcode.encode()
    |> :qrcode_demo.simple_png_encode()

  "data:image/png;base64," <> Base.encode64(png)
end
```

With `wkhtmltopdf`, data URIs need no `--enable-local-file-access` and can't fail to load. Encode the
**full verify URL**, not the bare serial — a phone camera should open the verification page directly.

### 4.5 Full issue → render → store → email flow

```elixir
defmodule Learning.Certificates.Issuer do
  alias Learning.{Certificates, Mailer}
  alias Learning.Certificates.Renderer

  @base_url "https://learn.example.com"

  def issue_and_deliver(user, course, attrs \\ %{}) do
    with {:ok, cert} <- Certificates.issue(user, course, attrs),
         {:ok, filename} <- render_pdf(cert),
         {:ok, cert} <- Certificates.update_certificate(cert, %{pdf_file: filename}) do
      Mailer.deliver_certificate(cert, pdf_url(cert))
      {:ok, cert}
    end
  end

  defp render_pdf(cert) do
    verify_url = "#{@base_url}/verify/#{cert.serial}"

    cert
    |> Renderer.to_html(verify_url, qr_data_uri(verify_url))
    |> Learning.PdfRenderer.html_to_pdf(basename: "certificate_#{cert.serial}")
  end

  defp pdf_url(%{pdf_file: file}), do: "#{@base_url}/uploads/#{URI.encode(file)}"

  defp qr_data_uri(verify_url) do
    png = verify_url |> :qrcode.encode() |> :qrcode_demo.simple_png_encode()
    "data:image/png;base64," <> Base.encode64(png)
  end
end
```

`Learning.PdfRenderer` is `SigningHelppp` from §2.1 with the hardcoded `terms_`/`signed_` prefixes
replaced by a `:basename` option, and `:erp_live` swapped for your OTP app name.

Note `render_pdf/1` runs `System.cmd` / `Port.open` — **seconds of blocking work**. Do not call it
inline from a LiveView `handle_event`; the process can't handle any other message meanwhile. Either
run it under a `Task.Supervisor` and message the LiveView on completion, or hand it to Oban:

```elixir
# In the LiveView, keep the UI responsive:
def handle_event("issue_certificate", %{"enrolment_id" => id}, socket) do
  enrolment = Courses.get_enrolment!(id)

  Task.Supervisor.async_nolink(Learning.TaskSupervisor, fn ->
    Learning.Certificates.Issuer.issue_and_deliver(enrolment.user, enrolment.course)
  end)

  {:noreply, socket |> assign(issuing: true) |> put_flash(:info, "Generating certificate…")}
end

def handle_info({ref, {:ok, cert}}, socket) do
  Process.demonitor(ref, [:flush])
  {:noreply, socket |> assign(issuing: false, cert: cert) |> put_flash(:info, "Certificate issued.")}
end

def handle_info({ref, {:error, reason}}, socket) do
  Process.demonitor(ref, [:flush])
  {:noreply, socket |> assign(issuing: false) |> put_flash(:error, "Failed: #{inspect(reason)}")}
end

def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}
```

### 4.6 Email delivery

`lib/erp_live/sgmail.ex:361` posts to the Mailjet REST API with Finch, embedding download links:

```elixir
def send_certificate(email, mem_id) do
  mem_id = to_string(mem_id)
  html = "...<a href='https://gs1kenya.org/uploads/certificate/membership_certificate#{mem_id}.pdf'>download here</a>..."

  headers = [
    {"Content-Type", "application/json"},
    {"Authorization", "Basic " <> Base.encode64("<api_key>:<secret>")}
  ]

  body = %{
    "Messages" => [
      %{
        "From" => %{"Email" => "no-reply@gs1kenya.org", "Name" => "GS1 Kenya"},
        "To"   => [%{"Email" => email, "Name" => ""}],
        "Subject" => "Your Certificates",
        "HTMLPart" => html
      }
    ]
  }

  :post
  |> Finch.build("https://api.mailjet.com/v3.1/send", headers, Jason.encode!(body))
  |> Finch.request(ErpLive.Finch)
  |> response()
end
```

Two things to change when you port it:

1. **The Mailjet key and secret are hardcoded in the source** at `sgmail.ex:445`. Read them from the
   environment in `runtime.exs` instead. (Worth rotating those existing credentials here too, since
   they're committed to git history.)
2. Certificates are delivered as **links to public `/uploads/` URLs**, which means anyone with the
   URL can fetch any certificate. For an e-learning site, either attach the PDF to the email or serve
   it through an authenticated controller.

Swiftmailer-style version with an attachment, using Swoosh:

```elixir
defmodule Learning.Mailer.Certificates do
  import Swoosh.Email
  alias Learning.Mailer

  def deliver_certificate(cert, pdf_path) do
    new()
    |> to({cert.learner_name, cert.user.email})
    |> from({"Learn Example", "no-reply@learn.example.com"})
    |> subject("Your certificate for #{cert.course_title}")
    |> html_body(body_html(cert))
    |> attachment(
      Swoosh.Attachment.new(pdf_path,
        filename: "#{cert.course_title} - Certificate.pdf",
        content_type: "application/pdf",
        type: :attachment
      )
    )
    |> Mailer.deliver()
  end

  defp body_html(cert) do
    """
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #1e3a8a;">Congratulations, #{cert.learner_name}!</h2>
      <p>You've completed <strong>#{cert.course_title}</strong>. Your certificate is attached.</p>
      <p>Anyone can verify it at
        <a href="https://learn.example.com/verify/#{cert.serial}">
          learn.example.com/verify/#{cert.serial}
        </a>
        &nbsp;(serial <strong>#{cert.serial}</strong>).
      </p>
      <p style="color: #666; font-size: 13px;">Learn Example &middot; Please do not reply.</p>
    </div>
    """
  end
end
```

Emails are network calls too — send them from the background task in §4.5, never inline.

### 4.7 Public verification page

The existing code has the lookup (`get_certificate_barcode/1` in `certificates.ex:80`) but no page.
Add one — it's what makes the serial and QR code worth printing:

```elixir
# router.ex — outside any auth pipeline
live "/verify/:serial", CertificateVerifyLive, :show

# lib/learning_web/live/certificate_verify_live.ex
def mount(%{"serial" => serial}, _session, socket) do
  {:ok, assign(socket, cert: Learning.Certificates.get_by_serial(serial), serial: serial)}
end
```

Render "Valid — issued to X for course Y on DATE" or "No valid certificate with this serial". Revoked
certificates must read as invalid, which is why `get_by_serial/1` filters on `status: "issued"`.

### 4.8 The learner-facing download button

```heex
<.certificate cert={@cert} verify_url={@verify_url} qr_data_uri={@qr_data_uri} />

<.button phx-hook="download_cert" id={"cert-download-#{@cert.id}"} style="margin-top: 10px;">
  Download
</.button>
```

The hook from §3 works unchanged — it keys off `cert-download-<id>` / `cert-only-<id>`, and the
component already sets that container id.

---

## 5. Checklist for the new project

**Dependencies**

```elixir
# mix.exs
{:pdf_generator, "~> 0.6.0"},   # optional — only if you keep the PdfGenerator API
{:qrcode, "~> 0.1.5"},          # verification QR
{:swoosh, "~> 1.5"},            # email with attachments
{:finch, "~> 0.16"}
```

**System packages** — install `wkhtmltopdf` (or Chrome/Chromium) in the Docker image, or the server
path silently degrades:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      wkhtmltopdf fonts-liberation \
    && rm -rf /var/lib/apt/lists/*
```

Missing fonts are the most common cause of "the PDF renders but the text looks wrong".

**Layout scripts** for the client-side path:

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
```

**Gotchas, condensed**

| Gotcha                                       | Fix                                                           |
| -------------------------------------------- | ------------------------------------------------------------- |
| Absolute paths like `/home/joss/...`         | `Path.join([:code.priv_dir(:app), "static", "uploads", ...])` |
| `~p` sigil for disk paths                    | `~p` is for routes only; use `Path.join/1`                    |
| `File.rename` tmp → priv fails with `:exdev` | `File.cp!/2` + `File.rm/1`                                    |
| Images blank in `html2canvas` output         | Await every `img.complete` before snapshotting                |
| Tailwind classes vanish in the PDF           | Inline `style` attributes only                                |
| Chrome hangs after `--print-to-pdf`          | Watch stdout for `bytes written to file`, cap with a deadline |
| PDF generation blocks the LiveView           | `Task.Supervisor.async_nolink` or Oban                        |
| Certificate text changes when a user renames | Snapshot `learner_name` / `course_title` at issue time        |
| Sequential serials are enumerable            | `:crypto.strong_rand_bytes/1`                                 |
| Public `/uploads/` exposes every certificate | Attach to email, or serve via an authorised controller        |
| API keys in source                           | `runtime.exs` + env vars                                      |
| `html2canvas` PDFs have no selectable text   | Use the server-side path when text matters                    |

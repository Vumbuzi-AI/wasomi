defmodule WasomiWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: WasomiWeb.Gettext
  use WasomiWeb, :verified_routes

  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  attr :dismissable, :boolean,
    default: true,
    doc:
      "when false, only the explicit close button dismisses the modal; " <>
        "click-away and Escape are disabled so in-progress form content " <>
        "can't be lost to a stray click or keypress"

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={if @dismissable, do: JS.exec("data-cancel", to: "##{@id}")}
              phx-key={if @dismissable, do: "escape"}
              phx-click-away={if @dismissable, do: JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a confirmation modal for an action gated behind an explicit "are
  you sure?" step (deleting a record, discarding drafts, etc.), replacing
  the browser's native `data-confirm` dialog with markup consistent with the
  rest of the admin UI.

  `:confirm` and `:cancel` are `Phoenix.LiveView.JS` commands, so the caller
  decides what actually happens — typically `JS.push("delete_x", value: ...)`
  and `JS.push("cancel_delete_x")` backed by a `deleting_x` assign that
  gates the modal with `:if`.

  ## Examples

      <.confirm_modal
        :if={@deleting_module}
        id="delete-module-modal"
        title={"Delete \"\#{@deleting_module.title}\"?"}
        confirm={JS.push("delete_module", value: %{id: @deleting_module.id})}
        cancel={JS.push("cancel_delete_module")}
      >
        This also removes all of its lectures. This can't be undone.
      </.confirm_modal>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :confirm, JS, required: true
  attr :cancel, JS, default: %JS{}
  attr :confirm_label, :string, default: "Delete"
  attr :variant, :atom, values: [:danger, :primary], default: :danger
  slot :inner_block, required: true

  def confirm_modal(assigns) do
    ~H"""
    <.modal id={@id} show on_cancel={@cancel}>
      <h2 class="text-lg font-semibold text-dark">{@title}</h2>
      <p class="mt-2 text-sm text-body">{render_slot(@inner_block)}</p>
      <div class="mt-6 flex items-center gap-4">
        <button
          type="button"
          phx-click={@confirm}
          class={[
            "rounded-full px-5 py-2 text-sm font-medium text-white transition",
            @variant == :danger && "bg-red-600 hover:bg-red-700",
            @variant == :primary && "bg-primary hover:bg-dark"
          ]}
        >
          {@confirm_label}
        </button>
        <button
          type="button"
          phx-click={@cancel}
          class="text-sm font-medium text-muted hover:text-dark"
        >
          Cancel
        </button>
      </div>
    </.modal>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"

  attr :auto_dismiss, :boolean,
    default: true,
    doc:
      "whether this flash hides itself ~5s after appearing (disable for connection-status flashes)"

  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook={if @auto_dismiss, do: "FlashAutoDismiss"}
      data-auto-dismiss-ms="5000"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 mr-2 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        auto_dismiss={false}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        auto_dismiss={false}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8 bg-white">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        "disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-zinc-900 disabled:active:text-white",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week)

  attr :field, FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="mt-2 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 min-h-[6rem]",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "date"} = assigns) do
    assigns = assign_new(assigns, :placeholder, fn -> nil end)

    ~H"""
    <div
      class="calendar-container relative"
      id={@id <> "-container"}
      phx-hook="DatePicker"
      data-max={@rest[:max] || assigns[:max]}
    >
      <.label :if={@label} for={@id}>{@label}</.label>
      <input
        type="hidden"
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value("date", @value)}
        data-dp-input
      />
      <button
        type="button"
        data-dp-trigger
        class={[
          "mt-2 flex w-full items-center justify-between gap-2 rounded-lg border bg-white px-3 py-2 text-left text-zinc-900 shadow-sm focus:ring-0 sm:text-sm sm:leading-6 cursor-pointer",
          @errors == [] && "border-zinc-300 hover:border-zinc-400 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
      >
        <span data-dp-display data-placeholder={@placeholder || "Choose a date"} class="text-sm">
          {Phoenix.HTML.Form.normalize_value("date", @value)}
        </span>
        <svg class="h-4 w-4 shrink-0 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
          />
        </svg>
      </button>

      <div
        data-dp-pop
        hidden
        class="calendar-popover absolute left-0 top-full z-50 mt-1.5 w-72 rounded-2xl border bg-white p-3.5 shadow-lg"
      >
        <div data-dp-body></div>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a design-system styled, icon-prefixed input for authentication
  surfaces (log in / sign up). `type="password"` automatically gets a
  show/hide toggle, wired up by the `TogglePassword` JS hook.

  ## Examples

      <.auth_input field={@form[:email]} type="email" label="Email address" required>
        <:icon><.icon name="hero-envelope" class="h-5 w-5" /></:icon>
      </.auth_input>
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(email password tel text url)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(autocomplete placeholder readonly required)
  slot :icon, required: true

  def auth_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> auth_input()
  end

  def auth_input(assigns) do
    assigns = assign(assigns, :toggle?, assigns.type == "password")

    ~H"""
    <div>
      <label :if={@label} for={@id} class="mb-2 block text-sm font-semibold text-dark">
        {@label}
      </label>
      <div
        id={@toggle? && "#{@id}-wrap"}
        phx-hook={@toggle? && "TogglePassword"}
        class={[
          "flex items-center gap-2 rounded-lg border bg-white px-3.5 py-3 transition",
          "focus-within:ring-4 focus-within:ring-primary/10",
          @errors == [] && "border-black/15 focus-within:border-primary",
          @errors != [] && "border-rose-400 focus-within:border-rose-400"
        ]}
      >
        <span class="shrink-0 text-muted">{render_slot(@icon)}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class="w-full border-0 bg-transparent p-0 font-medium text-dark outline-none placeholder:font-medium placeholder:text-muted focus:outline-none focus:ring-0"
          {@rest}
        />
        <button
          :if={@toggle?}
          type="button"
          data-role="toggle"
          aria-label="Show password"
          class="shrink-0 text-muted transition hover:text-dark"
        >
          <svg
            data-role="eye"
            class="h-4 w-4"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7Z" /><circle cx="12" cy="12" r="3" />
          </svg>
        </button>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders the shared split-screen shell for the log in / sign up pages: a
  fixed navy brand panel on the left, and a "Back to home" link plus a
  Log in/Sign up tab toggle above the caller's form content on the right.
  """
  attr :active, :atom, required: true, values: [:login, :register]
  slot :inner_block, required: true

  def auth_shell(assigns) do
    ~H"""
    <div class="grid min-h-screen lg:grid-cols-2">
      <div class="relative hidden flex-col justify-center bg-dark px-12 py-16 lg:sticky lg:top-0 lg:flex lg:h-screen xl:px-20">
        <a href="/" class="inline-flex items-center">
          <img src="/images/logo-reversed.png" alt="Wasomi" class="h-9 w-auto" />
        </a>
        <h1 class="mt-10 text-5xl font-bold leading-[1.05] text-white">
          Learn today. Use it at work tomorrow.
        </h1>
        <p class="mt-6 max-w-md text-white/70">
          Access practical GS1 learning, save your progress and continue from any device.
        </p>
      </div>

      <div class="flex flex-col px-6 py-6 sm:px-12 lg:py-8">
        <div class="flex justify-end">
          <a
            href="/"
            class="inline-flex items-center gap-2 text-sm font-semibold text-dark transition hover:text-primary"
          >
            <svg
              class="h-4 w-4"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <line x1="19" y1="12" x2="5" y2="12" /><polyline points="12 19 5 12 12 5" />
            </svg>
            Back to home
          </a>
        </div>

        <div class="mx-auto mt-6 w-full max-w-md flex-1">
          <div class="grid grid-cols-2 gap-1 rounded-xl bg-slate-100 p-1">
            <.link
              navigate={~p"/users/log_in"}
              class={[
                "rounded-lg py-2.5 text-center text-sm font-semibold transition",
                @active == :login && "bg-dark text-white",
                @active != :login && "text-dark hover:text-primary"
              ]}
            >
              Log in
            </.link>
            <.link
              navigate={~p"/users/register"}
              class={[
                "rounded-lg py-2.5 text-center text-sm font-semibold transition",
                @active == :register && "bg-dark text-white",
                @active != :register && "text-dark hover:text-primary"
              ]}
            >
              Sign up
            </.link>
          </div>

          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal">{col[:label]}</th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Hover tooltip for icon-only controls, styled to match the collapsed
  sidebar's tooltip. Give the trigger element `class="group relative"` so
  `group-hover:opacity-100` below picks it up — unlike the sidebar's version,
  this one isn't gated on any sidebar-collapsed state, so it works anywhere.

  ## Examples

      <.link href={...} class="group relative ..." aria-label="Export all payments as CSV">
        <.icon name="hero-document-arrow-down" class="h-5 w-5" />
        <.tooltip label="Export all payments as CSV" />
      </.link>
  """
  attr :label, :string, required: true

  def tooltip(assigns) do
    ~H"""
    <span class="pointer-events-none absolute left-1/2 top-full z-50 mt-2 -translate-x-1/2 whitespace-nowrap rounded-lg bg-dark px-2.5 py-1.5 text-xs font-medium text-white opacity-0 shadow-lg transition-opacity duration-150 group-hover:opacity-100">
      {@label}
    </span>
    """
  end

  @doc """
  Debounced search box for admin list views.

  Wraps its own `<form phx-change>` — the parent LiveView only needs a
  `handle_event(@event, %{@name => query}, socket)` clause. Emits changes
  after `@debounce` ms of inactivity so filtering doesn't run on every
  keystroke.

  ## Examples

      <.search_input value={@search} placeholder="Search course or slug" />
  """
  attr :value, :string, default: ""
  attr :name, :string, default: "q"
  attr :event, :string, default: "search"
  attr :placeholder, :string, default: "Search"
  attr :debounce, :integer, default: 300

  def search_input(assigns) do
    ~H"""
    <form phx-change={@event} class="relative">
      <.icon
        name="hero-magnifying-glass"
        class="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-muted"
      />
      <input
        type="search"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        phx-debounce={@debounce}
        class="h-11 w-64 rounded-full border border-black/10 bg-white pl-10 pr-4 text-sm text-dark placeholder:text-muted focus:border-primary focus:outline-none"
      />
    </form>
    """
  end

  @doc """
  Wraps admin list content with page-number navigation.

  Renders whatever's in the default slot as-is (each admin table has its
  own bespoke column layout, so this doesn't impose a shared table markup),
  followed by Previous/Next controls built from `@path_fn` — a
  `fun(page_number) -> path` the caller already has from its own filter/search
  query-param building. Hidden entirely when there's only one page. Previous
  is hidden (not just disabled) on page 1, and Next on the last page.

  ## Examples

      <.paginated_table page={@page.page} total_pages={@page.total_pages} path_fn={&courses_path(&1, @search)}>
        <div class="grid gap-7 sm:grid-cols-2 xl:grid-cols-3">
          <.course_card :for={course <- @page.entries} course={course} />
        </div>
      </.paginated_table>
  """
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :path_fn, :any, required: true
  slot :inner_block, required: true

  def paginated_table(assigns) do
    ~H"""
    <div>
      {render_slot(@inner_block)}
      <nav
        :if={@total_pages > 1}
        class="mt-6 grid grid-cols-3 items-center border-t border-black/5 pt-4"
      >
        <div class="justify-self-start">
          <.link
            :if={@page > 1}
            patch={@path_fn.(@page - 1)}
            class="inline-flex items-center gap-1 rounded-full border border-black/10 px-4 py-2 text-sm font-medium text-dark transition hover:border-primary hover:text-primary"
          >
            <.icon name="hero-chevron-left-mini" class="h-4 w-4" /> Previous
          </.link>
        </div>
        <span class="justify-self-center text-sm text-muted">Page {@page} of {@total_pages}</span>
        <div class="justify-self-end">
          <.link
            :if={@page < @total_pages}
            patch={@path_fn.(@page + 1)}
            class="inline-flex items-center gap-1 rounded-full border border-black/10 px-4 py-2 text-sm font-medium text-dark transition hover:border-primary hover:text-primary"
          >
            Next <.icon name="hero-chevron-right-mini" class="h-4 w-4" />
          </.link>
        </div>
      </nav>
    </div>
    """
  end

  @doc """
  A `<th>` that toggles server-side sort on click, with a chevron showing
  the current direction on whichever column is active.

  Column headers stay plain `<th>` text for columns the caller doesn't
  pass through this — sorting is opt-in per column, not all-or-nothing.

  ## Examples

      <.sortable_th
        label="Amount"
        field={:amount}
        current_sort_by={@sort_by}
        current_sort_dir={@sort_dir}
        path_fn={&payments_path(:payments, sort_by: &1, sort_dir: &2)}
      />
  """
  attr :label, :string, required: true
  attr :field, :atom, required: true
  attr :current_sort_by, :atom, required: true
  attr :current_sort_dir, :atom, required: true
  attr :path_fn, :any, required: true, doc: "fun(field, next_dir) -> path"

  def sortable_th(assigns) do
    active? = assigns.field == assigns.current_sort_by
    next_dir = if active? and assigns.current_sort_dir == :asc, do: :desc, else: :asc

    assigns = assign(assigns, active?: active?, next_dir: next_dir)

    ~H"""
    <th class="px-4 py-3 font-semibold">
      <.link
        patch={@path_fn.(@field, @next_dir)}
        class={["inline-flex items-center gap-1 hover:text-dark", @active? && "text-dark"]}
      >
        {@label}
        <.icon
          :if={@active?}
          name={
            if @current_sort_dir == :asc, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"
          }
          class="h-3 w-3"
        />
      </.link>
    </th>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(WasomiWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(WasomiWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end

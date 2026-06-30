# Wasomi Design System

This document captures the visual language used across Wasomi. Follow it when
building new pages and components so the UI stays consistent. The source of
truth for tokens is [`assets/tailwind.config.js`](assets/tailwind.config.js);
the reference implementation of these patterns lives in
[`lib/wasomi_web/components/home_components.ex`](lib/wasomi_web/components/home_components.ex).

## Colors

Defined under `theme.extend.colors` in the Tailwind config. Always use the
semantic token names — never hard-code hex values in markup.

| Token       | Hex       | Usage |
|-------------|-----------|-------|
| `primary`   | `#009d77` | Brand green — primary actions, links, active/hover accents, logo mark |
| `dark`      | `#011813` | Headings, primary text, dark buttons, dark badges |
| `body`      | `#4e5255` | Body / paragraph text |
| `muted`     | `#98a2b3` | Secondary text, icon strokes, de-emphasized labels |
| `secondary` | `#ea4c89` | Pink accent — sparingly, for highlights/gradients |
| `soft`      | `#f8f8f8` | Alternating section backgrounds |
| `mint`      | `#f0fdf9` | Pale green — pill/badge backgrounds, hero gradient, hover fills |

Conventions:
- **Headings:** `text-dark`. **Body copy:** `text-body`. **Muted/meta:** `text-muted`.
- **Links & accents:** `text-primary`, with `hover:text-primary` on neutral links.
- On dark/gradient backgrounds use `text-white`, `text-white/80`, `text-white/70`
  for primary/secondary/tertiary text respectively.
- Hairline borders use alpha black: `border-black/5` (cards) and `border-black/10`
  (inputs, icon buttons, pills).

## Typography

- **Font family:** `Outfit` (loaded via Google Fonts in
  [`assets/css/app.css`](assets/css/app.css), set as the default `sans` stack).
- **Weights in use:** `font-medium` (500), `font-semibold` (600), `font-bold` (700).
  Headings are `font-semibold`; the logo wordmark is `font-bold`.
- **Type scale:**
  - Hero `h1`: `text-4xl sm:text-5xl lg:text-6xl` with `leading-[1.1]`
  - Section `h2`: `text-3xl sm:text-4xl lg:text-5xl`
  - Card / sub headings `h3`: `text-lg font-medium`
  - Lead paragraph: `text-lg text-body`
  - Body: default size, `text-body`
  - Meta / labels: `text-sm`, fine print `text-xs`

## Layout

- **Page container:** `mx-auto max-w-container px-5 lg:px-8`
  (`max-w-container` = `1240px`). Use this wrapper inside every section.
- **Section rhythm:** vertical padding `py-20 lg:py-28`. Alternate background
  between default white and `bg-soft` to separate sections.
- **Grids:** content splits use `grid gap-12 lg:grid-cols-2`; card listings use
  `grid gap-7 md:grid-cols-2 lg:grid-cols-3` (cards `gap-7`).
- **Section headings** are usually centered: `text-center`, often with
  `mx-auto max-w-2xl` to constrain width.

## Components & Patterns

### Buttons

Primary (filled, dark → green on hover) with trailing circular arrow:
```html
<a class="group inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary">
  Label
  <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
    <!-- arrow icon -->
  </span>
</a>
```

Secondary (outline, fills dark on hover):
```html
<a class="group inline-flex items-center gap-2 rounded-full border border-dark py-1.5 pl-6 pr-1.5 font-medium text-dark transition hover:bg-dark hover:text-white">
  Label
  <span class="grid h-9 w-9 place-items-center rounded-full bg-dark text-white transition group-hover:bg-primary"> … </span>
</a>
```

Rules: buttons are always **pill-shaped** (`rounded-full`), asymmetric padding
(`pl-6 pr-1.5`) to seat the trailing `h-9 w-9` circular icon, `font-medium`,
and `transition` on color. Use the `group` / `group-hover:` swap for the icon.

### Pills / Badges

- Category tag: `rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary`
- Tab (inactive): `rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-medium text-dark`
- Tab (active): adds `border-primary bg-primary text-white` (driven by
  `peer-checked/*` on a hidden radio).

### Cards

```html
<a class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl">
  <div class="overflow-hidden">
    <img class="h-56 w-full object-cover transition duration-500 group-hover:scale-105" />
  </div>
  <div class="p-6"> … </div>
</a>
```

Card conventions: `rounded-3xl`, `border-black/5`, `bg-white`, `overflow-hidden`,
`hover:shadow-xl`, and a `group-hover:scale-105` zoom on the image. Inner padding `p-6`.

### Forms / Inputs

- `@tailwindcss/forms` plugin is enabled.
- Inputs are pill-shaped on marketing surfaces: `rounded-full … outline-none
  placeholder:text-body`. Email-capture pattern wraps an input + button inside a
  `rounded-full bg-white p-2` container.

### Icons

- Inline SVGs, `viewBox="0 0 24 24"`, `fill="none" stroke="currentColor"`,
  `stroke-width="2"`, `stroke-linecap="round" stroke-linejoin="round"`.
- Sizes: `h-4 w-4` (in buttons), `h-5 w-5` (inline/meta), `h-7 w-7`+ (feature).
- Heroicons are available via the `hero-*` classes (config plugin) for
  `CoreComponents.icon/1`.
- Circular icon button: `grid h-10 w-10 place-items-center rounded-full
  border border-black/10 text-muted hover:border-primary hover:text-primary`.

## Rounding, Shadow & Effects

- **Radii:** pills `rounded-full`; cards `rounded-3xl`; floating panels
  `rounded-2xl`; large feature blocks `rounded-[28px]` / `rounded-[32px]`;
  logo mark `rounded-[10px]`.
- **Shadows:** `shadow-lg` and `shadow-xl` for floating/overlay elements;
  `hover:shadow-xl` on cards; `shadow-2xl` on hero imagery.
- **Transitions:** add `transition` to anything interactive; image zooms use
  `transition duration-500`.
- **Gradients:** hero uses `bg-gradient-to-b from-mint via-white to-white`;
  the CTA banner uses `bg-gradient-to-r from-indigo-600 via-primary to-secondary`.
- **Overlays on imagery:** glass cards use `bg-white/95 … backdrop-blur`.

## Responsive

- Mobile-first. Primary breakpoints: `sm:`, `md:`, `lg:`.
- Navigation collapses below `lg` into a peer-checkbox toggle menu; desktop nav
  appears at `lg:`.
- Type and grids scale up at `sm:`/`lg:` (see Typography & Layout).

## Interaction (CSS-only state)

The home page favors stateless, CSS-only interactivity rather than JS:
- **Mobile menu:** hidden `peer` checkbox + `peer-checked:flex`.
- **Dropdowns:** `group` + `group-hover:flex group-focus-within:flex`.
- **Tabs:** named peers (`peer/a`, `peer-checked/a:*`) on hidden radios.

Prefer these patterns for simple toggles; reach for LiveView/JS only when state
must be shared or persisted.

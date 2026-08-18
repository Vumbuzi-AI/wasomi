// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/wasomi_web.ex",
    "../lib/wasomi_web/**/*.*ex",
  ],
  theme: {
    extend: {
      colors: {
        primary: "#f97316",
        dark: "#012c6a",
        // Navy is the structural app colour (headings, strong actions and
        // navigation); orange remains the high-energy accent for progress,
        // focus and calls to action.
        ink: "#012c6a",
        body: "#404040",
        muted: "#a3a3a3",
        secondary: "#012c6a",
        soft: "#ffffff",
        mint: "#fff7ed",
      },
      fontFamily: {
        sans: ["Outfit", "ui-sans-serif", "system-ui", "sans-serif"],
      },
      maxWidth: { container: "1240px" },
      keyframes: {
        "checklist-in": {
          "0%": { opacity: "0", transform: "translateY(4px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        "fade-up": {
          "0%": { opacity: "0", transform: "translateY(16px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        "image-in": {
          "0%": { opacity: "0", transform: "scale(1.08) translateX(12px)" },
          "100%": { opacity: "1", transform: "scale(1) translateX(0)" },
        },
        float: {
          "0%, 100%": { transform: "translateY(0)" },
          "50%": { transform: "translateY(-6px)" },
        },
      },
      animation: {
        "checklist-in": "checklist-in 0.25s ease-out forwards",
        // Same cubic-bezier as `.animate-fade-in` in app.css, so on-load and
        // on-reveal content share one easing curve — just a bigger rise than
        // checklist-in's 4px, sized for headline-level content.
        "fade-up": "fade-up 0.6s cubic-bezier(0.2, 0, 0, 1) forwards",
        "image-in": "image-in 0.8s cubic-bezier(0.2, 0, 0, 1) forwards",
        float: "float 5s cubic-bezier(0.45, 0, 0.55, 1) infinite",
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        ".phx-click-loading&",
        ".phx-click-loading &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        ".phx-submit-loading&",
        ".phx-submit-loading &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        ".phx-change-loading&",
        ".phx-change-loading &",
      ]),
    ),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized");
      let values = {};
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"],
      ];
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach((file) => {
          let name = path.basename(file, ".svg") + suffix;
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) };
        });
      });
      matchComponents(
        {
          hero: ({ name, fullPath }) => {
            let content = fs
              .readFileSync(fullPath)
              .toString()
              .replace(/\r?\n|\r/g, "");
            let size = theme("spacing.6");
            if (name.endsWith("-mini")) {
              size = theme("spacing.5");
            } else if (name.endsWith("-micro")) {
              size = theme("spacing.4");
            }
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              "-webkit-mask": `var(--hero-${name})`,
              mask: `var(--hero-${name})`,
              "mask-repeat": "no-repeat",
              "background-color": "currentColor",
              "vertical-align": "middle",
              display: "inline-block",
              width: size,
              height: size,
            };
          },
        },
        { values },
      );
    }),
  ],
};

import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: "#E31E24",
          dark: "#A32D2D",
        },
      },
    },
  },
  plugins: [],
};
export default config;
import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/app/**/*.{ts,tsx}",
    "./src/components/**/*.{ts,tsx}",
    "./src/lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          50: "#f2fbf7",
          100: "#dff7ea",
          200: "#c0edd7",
          300: "#92ddbb",
          400: "#5ec699",
          500: "#35ab7b",
          600: "#23895f",
          700: "#1d6d4d",
          800: "#1a573f",
          900: "#184835",
          950: "#0b281d",
        },
      },
      boxShadow: {
        soft: "0 12px 30px rgba(2, 6, 23, 0.08)",
      },
    },
  },
  plugins: [],
};

export default config;

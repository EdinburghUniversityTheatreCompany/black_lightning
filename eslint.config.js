import js from "@eslint/js";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    files: [
      "app/javascript/controllers/**/*.js",
      "app/javascript/lib/**/*.js",
    ],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {
        ...globals.browser,
        Swal: "readonly",   // SweetAlert2 loaded as global
        Turbo: "readonly",  // Turbo loaded as global
      },
    },
    rules: {
      "no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "no-console": "warn",
      "prefer-const": "error",
      "no-var": "error",
    },
  },
];

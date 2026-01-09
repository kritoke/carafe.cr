require "../plugin"
require "../site"
require "../config"
require "liquid"

module Carafe::Plugins::CarafeDarkMode
  # Dark Mode Generator - generates CSS and JS for dark mode toggle
  class DarkModeGenerator
    def generate_css : String
      <<-CSS
      /* Dark Mode Styles */
      :root {
        --dark-mode-text-color: #e0e0e0;
        --dark-mode-bg-color: #1a1a1a;
        --dark-mode-sidebar-bg: #2d2d2d;
        --dark-mode-border-color: #404040;
        --dark-mode-link-color: #64b5f6;
        --dark-mode-code-bg: #2d2d2d;
      }

      /* Minimal Mistakes Dark Skin - Applied when skin-dark class is on html element */
      html.skin-dark body {
        color: #eaeaea !important;
        background-color: transparent !important;
      }

      html.skin-dark .masthead,
      html.skin-dark .masthead__inner-wrap,
      html.skin-dark .masthead__menu {
        background-color: transparent !important;
        border-bottom: 1px solid #51555d !important;
      }

      html.skin-dark nav.greedy-nav,
      html.skin-dark .greedy-nav .visible-links,
      html.skin-dark .greedy-nav .hidden-links,
      html.skin-dark .greedy-nav li,
      html.skin-dark .greedy-nav li a {
        background-color: #252a34 !important;
      }

      html.skin-dark .greedy-nav .visible-links a,
      html.skin-dark .greedy-nav li a {
        color: #eaeaea !important;
      }

      html.skin-dark .greedy-nav .visible-links a:hover,
      html.skin-dark .greedy-nav li a:hover {
        color: #8cd2d5 !important;
      }

      html.skin-dark .hidden-links.hidden,
      html.skin-dark .greedy-nav__toggle {
        background-color: #252a34 !important;
        border: 1px solid #51555d !important;
      }

      html.skin-dark .page__content {
        color: #eaeaea !important;
      }

      html.skin-dark .page__title,
      html.skin-dark h1,
      html.skin-dark h2,
      html.skin-dark h4,
      html.skin-dark h5,
      html.skin-dark h6 {
        color: #eaeaea !important;
      }

      html.skin-dark h3 {
        color: #eeeeee !important;
      }

      html.skin-dark a {
        color: #8cd2d5 !important;
      }

      html.skin-dark code,
      html.skin-dark pre {
        background-color: #252a34 !important;
        border-color: #51555d !important;
        color: #eaeaea !important;
      }

      html.skin-dark blockquote {
        border-left-color: #8cd2d5 !important;
        background-color: #252a34 !important;
        color: #b0b0b0 !important;
      }

      html.skin-dark table,
      html.skin-dark th,
      html.skin-dark td {
        border-color: #51555d !important;
      }

      html.skin-dark th,
      html.skin-dark tr:nth-child(even) {
        background-color: #252a34 !important;
      }

      html.skin-dark .page__footer,
      html.skin-dark .page__footer-follow,
      html.skin-dark .page__footer-copyright {
        background-color: #1a1d24 !important;
        border-top: 1px solid #eeeeee !important;
        color: #eeeeee !important;
      }

      html.skin-dark .page__footer a {
        color: #8cd2d5 !important;
      }

      html.skin-dark .sidebar,
      html.skin-dark .sidebar__right,
      html.skin-dark .author__urls-wrapper {
        background-color: #252a34 !important;
        border-color: #51555d !important;
      }

      html.skin-dark .author__content p,
      html.skin-dark .author__name {
        color: #eaeaea !important;
      }

      html.skin-dark .archive__item,
      html.skin-dark .list__item,
      html.skin-dark .feature__wrapper {
        border-color: #51555d !important;
      }

      html.skin-dark .archive__item-title {
        color: #eaeaea !important;
      }

      html.skin-dark .archive__item-title a {
        color: #8cd2d5 !important;
      }

      html.skin-dark .archive__item-excerpt,
      html.skin-dark .archive__item-teaser {
        color: #eaeaea !important;
      }

      /* Toggle-based dark mode styles */
      body.dark-mode {
        color: var(--dark-mode-text-color);
        background-color: var(--dark-mode-bg-color);
      }

      body.dark-mode .masthead {
        background-color: var(--dark-mode-sidebar-bg);
        border-bottom: 1px solid var(--dark-mode-border-color);
      }

      body.dark-mode .sidebar {
        background-color: var(--dark-mode-sidebar-bg);
      }

      body.dark-mode .page__content {
        color: var(--dark-mode-text-color);
      }

      body.dark-mode .page__title,
      body.dark-mode h1,
      body.dark-mode h2,
      body.dark-mode h3,
      body.dark-mode h4,
      body.dark-mode h5,
      body.dark-mode h6 {
        color: var(--dark-mode-text-color);
      }

      body.dark-mode a {
        color: var(--dark-mode-link-color);
      }

      body.dark-mode code,
      body.dark-mode pre {
        background-color: var(--dark-mode-code-bg);
        border-color: var(--dark-mode-border-color);
      }

      body.dark-mode blockquote {
        border-left-color: var(--dark-mode-link-color);
      }

      body.dark-mode table {
        border-color: var(--dark-mode-border-color);
      }

      body.dark-mode td,
      body.dark-mode th {
        border-color: var(--dark-mode-border-color);
      }

      body.dark-mode .page__footer {
        background-color: var(--dark-mode-sidebar-bg);
        border-top: 1px solid var(--dark-mode-border-color);
      }

      body.dark-mode .masthead__menu,
      body.dark-mode .author__urls,
      body.dark-mode .sidebar__right {
        background-color: var(--dark-mode-sidebar-bg);
      }

      /* Dark mode toggle button */
      .dark-mode-toggle {
        position: fixed;
        bottom: 20px;
        right: 20px;
        z-index: 1000;
        background: var(--dark-mode-sidebar-bg);
        border: 2px solid var(--dark-mode-border-color);
        color: var(--dark-mode-text-color);
        padding: 10px 15px;
        border-radius: 5px;
        cursor: pointer;
        transition: all 0.3s ease;
      }

      .dark-mode-toggle:hover {
        background: var(--dark-mode-link-color);
        color: white;
      }

      /* Smooth transitions */
      body,
      .masthead,
      .sidebar,
      .page__content,
      .page__footer {
        transition: background-color 0.3s ease, color 0.3s ease;
      }
      CSS
    end

    def generate_js : String
      <<-JS
      (function() {
        'use strict';

        // Check for saved preference or system preference
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        const savedTheme = localStorage.getItem('theme');
        const shouldUseDark = savedTheme === 'dark' || (!savedTheme && prefersDark);

        function setTheme(isDark) {
          if (isDark) {
            document.body.classList.add('dark-mode');
            localStorage.setItem('theme', 'dark');
            const toggle = document.querySelector('.dark-mode-toggle');
            if (toggle) toggle.textContent = '☀️ Light';
          } else {
            document.body.classList.remove('dark-mode');
            localStorage.setItem('theme', 'light');
            const toggle = document.querySelector('.dark-mode-toggle');
            if (toggle) toggle.textContent = '🌙 Dark';
          }
        }

        function toggleTheme() {
          const isDark = document.body.classList.contains('dark-mode');
          setTheme(!isDark);
        }

        // Initialize theme on page load
        setTheme(shouldUseDark);

        // Create and inject toggle button
        function createToggleButton() {
          const toggle = document.createElement('button');
          toggle.className = 'dark-mode-toggle';
          toggle.textContent = shouldUseDark ? '☀️ Light' : '🌙 Dark';
          toggle.setAttribute('aria-label', 'Toggle dark mode');
          toggle.onclick = toggleTheme;
          document.body.appendChild(toggle);
        }

        // Wait for DOM to be ready
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', createToggleButton);
        } else {
          createToggleButton();
        }

        // Expose toggle function globally for manual triggering
        window.toggleDarkMode = toggleTheme;
      })();
      JS
    end

    def generate_html_injection : String
      <<-HTML
      <style>
        #{generate_css}
      </style>
      <script>
        #{generate_js}
      </script>
      HTML
    end
  end

  # Module method to generate dark mode assets
  def self.generate_assets : NamedTuple(css: String, js: String, html: String)
    generator = DarkModeGenerator.new
    {
      css: generator.generate_css,
      js: generator.generate_js,
      html: generator.generate_html_injection
    }
  end
end

# Plugin class
class Carafe::Plugins::CarafeDarkMode::Plugin < Carafe::Plugin
  def name : String
    "carafe_dark_mode"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    # Check if dark_mode is enabled in config
    dark_mode_enabled = config["dark_mode"]?
    return true if dark_mode_enabled.nil? # Default to enabled if not specified

    dark_mode_enabled.as_bool? || (dark_mode_enabled.as_s? == "true")
  end

  def register(site : Carafe::Site) : Nil
    puts "CarafeDarkMode: Registering dark mode plugin" unless site.config.quiet?
    # Plugin doesn't need to register filters or generators
    # It works by injecting assets during page processing
  end
end

# Register this plugin
Carafe::Plugin.register_implementation(Carafe::Plugins::CarafeDarkMode::Plugin)

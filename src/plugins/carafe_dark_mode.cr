require "../plugin"
require "../site"
require "../config"
require "liquid"

module Carafe::Plugins::CarafeDarkMode
  # Dark Mode Generator - generates CSS and JS for dark mode toggle
  class DarkModeGenerator
    def generate_css : String
      <<-CSS
      /* Minimal Mistakes Dark Skin - Applied when skin-dark class is present */
      html.skin-dark {
        /* Base variables for dark skin */
        --background-color: #1a1d24;
        --text-color: #eaeaea;
        --primary-color: #64b5f6;
        --border-color: #51555d;
        --nav-background: #252a34;
        --sidebar-background: #252a34;
        --footer-background: #1a1d24;
      }

      html.skin-dark body {
        color: #eaeaea !important;
      }

      html.skin-dark .masthead,
      html.skin-dark .masthead__inner-wrap,
      html.skin-dark .masthead__menu {
        background-color: transparent !important;
        border-bottom: 1px solid #51555d !important;
      }

      /* Navigation */
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
        color: #64b5f6 !important;
      }

      /* Hidden links dropdown */
      html.skin-dark .hidden-links.hidden,
      html.skin-dark .greedy-nav__toggle {
        background-color: #252a34 !important;
        border: 1px solid #51555d !important;
      }

      /* Main content area */
      html.skin-dark .page__wrapper,
      html.skin-dark .page,
      html.skin-dark .page__inner-wrap,
      html.skin-dark .page__content,
      html.skin-dark .page__share,
      html.skin-dark .page__related,
      html.skin-dark .page__comments {
        color: #eaeaea !important;
      }

      /* Headings */
      html.skin-dark .page__title,
      html.skin-dark h1,
      html.skin-dark h2,
      html.skin-dark h3,
      html.skin-dark h4,
      html.skin-dark h5,
      html.skin-dark h6 {
        color: #eaeaea !important;
      }

      /* Links */
      html.skin-dark a,
      html.skin-dark .page__content a {
        color: #64b5f6 !important;
      }

      html.skin-dark a:hover,
      html.skin-dark .page__content a:hover {
        color: #90caf9 !important;
      }

      /* Sidebar */
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

      /* Footer */
      html.skin-dark .page__footer,
      html.skin-dark .page__footer-follow,
      html.skin-dark .page__footer-copyright {
        background-color: #1a1d24 !important;
        border-top: 1px solid #eeeeee !important;
        color: #eeeeee !important;
      }

      html.skin-dark .page__footer a {
        color: #64b5f6 !important;
      }

      /* Archive and list items */
      html.skin-dark .archive__item,
      html.skin-dark .list__item,
      html.skin-dark .feature__wrapper {
        border-color: #51555d !important;
      }

      html.skin-dark .archive__item-title,
      html.skin-dark .archive__item-title a {
        color: #eaeaea !important;
      }

      html.skin-dark .archive__item-excerpt,
      html.skin-dark .archive__item-teaser {
        color: #b0b0b0 !important;
      }

      /* Code blocks */
      html.skin-dark code,
      html.skin-dark pre,
      html.skin-dark .highlight {
        background-color: #252a34 !important;
        border-color: #51555d !important;
        color: #eaeaea !important;
      }

      html.skin-dark code::-webkit-scrollbar,
      html.skin-dark pre::-webkit-scrollbar {
        background: #252a34 !important;
      }

      /* Blockquotes */
      html.skin-dark blockquote {
        border-left-color: #64b5f6 !important;
        background-color: #252a34 !important;
        color: #b0b0b0 !important;
      }

      /* Tables */
      html.skin-dark table,
      html.skin-dark th,
      html.skin-dark td {
        border-color: #51555d !important;
      }

      html.skin-dark th,
      html.skin-dark tr:nth-child(even) {
        background-color: #252a34 !important;
      }

      /* Forms and inputs */
      html.skin-dark input,
      html.skin-dark textarea,
      html.skin-dark select {
        background-color: #252a34 !important;
        border-color: #51555d !important;
        color: #eaeaea !important;
      }

      html.skin-dark input:focus,
      html.skin-dark textarea:focus,
      html.skin-dark select:focus {
        border-color: #64b5f6 !important;
      }

      /* Buttons */
      html.skin-dark .btn,
      html.skin-dark button {
        background-color: #252a34 !important;
        color: #eaeaea !important;
        border-color: #51555d !important;
      }

      html.skin-dark .btn:hover,
      html.skin-dark button:hover {
        background-color: #64b5f6 !important;
        color: white !important;
      }

      /* Pagination */
      html.skin-dark .pagination,
      html.skin-dark .pager li a,
      html.skin-dark .pager li span {
        background-color: #252a34 !important;
        border-color: #51555d !important;
        color: #eaeaea !important;
      }

      html.skin-dark .pagination li a:hover,
      html.skin-dark .pagination li.current a {
        background-color: #64b5f6 !important;
        color: white !important;
      }

      /* Search */
      html.skin-dark .search__input {
        background-color: #252a34 !important;
        border-color: #51555d !important;
        color: #eaeaea !important;
      }

      html.skin-dark .search__results {
        background-color: #252a34 !important;
        border-color: #51555d !important;
      }

      /* Algolia search */
      html.skin-dark .ais-Hits,
      html.skin-dark .ais-Hits-list,
      html.skin-dark .ais-Hit {
        background-color: #252a34 !important;
        color: #eaeaea !important;
      }

      /* Dark mode toggle button */
      .dark-mode-toggle {
        position: fixed !important;
        bottom: 20px !important;
        right: 20px !important;
        z-index: 9999 !important;
        background: #252a34 !important;
        border: 2px solid #51555d !important;
        color: #eaeaea !important;
        padding: 10px 15px !important;
        border-radius: 5px !important;
        cursor: pointer !important;
        transition: all 0.3s ease !important;
        font-size: 14px !important;
      }

      .dark-mode-toggle:hover {
        background: #64b5f6 !important;
        color: white !important;
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
        const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
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

        // Create and inject toggle button
        function createToggleButton() {
          // Don't create if it already exists
          if (document.querySelector('.dark-mode-toggle')) {
            return;
          }

          const toggle = document.createElement('button');
          toggle.className = 'dark-mode-toggle';
          toggle.textContent = shouldUseDark ? '☀️ Light' : '🌙 Dark';
          toggle.setAttribute('aria-label', 'Toggle dark mode');
          toggle.onclick = toggleTheme;
          document.body.appendChild(toggle);

          // Initialize theme after button is created
          setTheme(shouldUseDark);
        }

        // Wait for DOM to be fully ready
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', createToggleButton);
        } else if (document.readyState === 'interactive') {
          // DOM is ready but stylesheets/images might not be loaded
          // Use setTimeout to ensure body is available
          window.setTimeout(createToggleButton, 0);
        } else {
          // DOM is already fully loaded
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

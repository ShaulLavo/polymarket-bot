defmodule PolymarketBot.ErrorHTML do
  @moduledoc """
  Terminal-style error pages.
  """

  def render(template, _assigns) do
    error_code = template |> String.replace(".html", "")

    """
    <!DOCTYPE html>
    <html class="h-full bg-black">
    <head>
      <meta charset="utf-8">
      <title>ERROR #{error_code}</title>
      <style>
        body {
          background: black;
          color: #00ff00;
          font-family: monospace;
          display: flex;
          align-items: center;
          justify-content: center;
          height: 100vh;
          margin: 0;
        }
        .container {
          text-align: center;
          border: 1px solid rgba(0, 255, 0, 0.3);
          padding: 40px;
        }
        .code {
          font-size: 4rem;
          color: #ff6b6b;
        }
        .message {
          color: rgba(0, 255, 0, 0.7);
          margin-top: 20px;
        }
        a {
          color: #ffd93d;
          text-decoration: none;
        }
        a:hover {
          text-decoration: underline;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <pre>███████╗██████╗ ██████╗  ██████╗ ██████╗
██╔════╝██╔══██╗██╔══██╗██╔═══██╗██╔══██╗
█████╗  ██████╔╝██████╔╝██║   ██║██████╔╝
██╔══╝  ██╔══██╗██╔══██╗██║   ██║██╔══██╗
███████╗██║  ██║██║  ██║╚██████╔╝██║  ██║
╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝</pre>
        <div class="code">#{error_code}</div>
        <div class="message">[SYSTEM ERROR] Request could not be processed</div>
        <div style="margin-top: 30px;">
          <a href="/">[RETURN TO TERMINAL]</a>
        </div>
      </div>
    </body>
    </html>
    """
  end
end

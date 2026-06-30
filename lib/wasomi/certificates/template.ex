defmodule Wasomi.Certificates.Template do
  @moduledoc """
  Branded HEEx certificate template.
  """

  use Phoenix.Component

  def render_html(assigns) do
    assigns
    |> certificate()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :learner_name, :string, required: true
  attr :title, :string, required: true
  attr :type_label, :string, required: true
  attr :issued_on, :string, required: true
  attr :serial_number, :string, required: true

  def certificate(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <style>
          * { box-sizing: border-box; }
          html, body { margin: 0; width: 100%; height: 100%; }
          body {
            color: #011813;
            font-family: "Arial", "Helvetica", sans-serif;
            text-rendering: geometricPrecision;
          }
          .page {
            position: relative;
            display: flex;
            width: 100vw;
            height: 100vh;
            padding: 34px;
            overflow: hidden;
            background:
              radial-gradient(circle at 9% 8%, #f0fdf9 0, #f0fdf9 18%, transparent 42%),
              radial-gradient(circle at 92% 90%, rgba(234, 76, 137, .10) 0, transparent 35%),
              #ffffff;
          }
          .frame {
            position: relative;
            display: flex;
            flex: 1;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            border: 2px solid #009d77;
            border-radius: 28px;
            padding: 60px 90px 46px;
            text-align: center;
          }
          .frame:before, .frame:after {
            position: absolute;
            width: 110px;
            height: 110px;
            border: 14px solid #011813;
            content: "";
          }
          .frame:before {
            top: -2px; left: -2px;
            border-right: 0; border-bottom: 0;
            border-radius: 26px 0 0 0;
          }
          .frame:after {
            right: -2px; bottom: -2px;
            border-top: 0; border-left: 0;
            border-radius: 0 0 26px 0;
          }
          .brand { display: flex; align-items: center; gap: 12px; }
          .mark {
            display: grid;
            width: 48px; height: 48px;
            place-items: center;
            border-radius: 12px;
            background: #009d77;
            color: white;
            font-size: 28px;
            font-weight: 700;
          }
          .wordmark { text-align: left; font-size: 21px; font-weight: 700; line-height: 1.05; }
          .wordmark span { display: block; color: #4e5255; font-size: 11px; font-weight: 600; letter-spacing: .16em; text-transform: uppercase; }
          .eyebrow { margin-top: 38px; color: #009d77; font-size: 14px; font-weight: 700; letter-spacing: .22em; text-transform: uppercase; }
          h1 { margin: 14px 0 0; font-family: Georgia, serif; font-size: 48px; font-weight: 500; }
          .copy { margin-top: 22px; color: #4e5255; font-size: 17px; }
          .name {
            margin-top: 10px;
            padding: 0 34px 8px;
            border-bottom: 2px solid #009d77;
            font-family: Georgia, serif;
            font-size: 35px;
            font-weight: 600;
          }
          .title { max-width: 850px; margin-top: 22px; font-size: 25px; font-weight: 600; line-height: 1.25; }
          .meta { display: flex; margin-top: 38px; gap: 64px; color: #4e5255; font-size: 12px; }
          .meta strong { display: block; margin-bottom: 5px; color: #011813; font-size: 14px; }
          .seal {
            position: absolute;
            right: 66px; top: 52px;
            display: grid;
            width: 88px; height: 88px;
            place-items: center;
            border: 2px solid #009d77;
            border-radius: 50%;
            color: #009d77;
            font-size: 11px;
            font-weight: 700;
            letter-spacing: .10em;
            line-height: 1.25;
            text-transform: uppercase;
          }
        </style>
      </head>
      <body>
        <main class="page">
          <section class="frame">
            <div class="seal">Wasomi<br />Certified</div>
            <div class="brand">
              <div class="mark">K</div>
              <div class="wordmark">Wasomi <span>Business Institute</span></div>
            </div>
            <div class="eyebrow">{@type_label}</div>
            <h1>Certificate of Completion</h1>
            <div class="copy">This certifies that</div>
            <div class="name">{@learner_name}</div>
            <div class="copy">has successfully completed</div>
            <div class="title">{@title}</div>
            <div class="meta">
              <div><strong>{@issued_on}</strong>Date issued</div>
              <div><strong>{@serial_number}</strong>Certificate serial</div>
            </div>
          </section>
        </main>
      </body>
    </html>
    """
  end
end

# Sending Emails using Amazon SES

## What we are going to do

We are going to build an application which sends an email using Amazon SES
using the SMTP interface described [here](http://docs.aws.amazon.com/ses/latest/DeveloperGuide/sending-email.html).
If you are looking to integrate emailing in your application, I would advise
against immediately trying to integrate this in before having already created
a throwaway application.

## Tools we are going to use

### Bamboo

<img src="https://avatars1.githubusercontent.com/u/6183?v=3&s=200" align="right" height="150px" />

Bamboo is an emailing library for Elixir built by [thoughtbot](https://thoughtbot.com/)

We will use the [SMTP adapter](https://github.com/fewlinesco/bamboo_smtp)

We are also going to use [mock](https://github.com/jjh42/mock) for stubbing
our functions when testing

<br>

----

### Amazon SES

<img src="https://pbs.twimg.com/profile_images/646830789787697153/NKoHyhZZ.png" align="right" height="150px" />

SES is an email service provided by Amazon.

SES is reliable, affordable and has great documentation.

<br><br><br>

## How we are going to do it

We will divide the setup into two sections; the SES setup and the Phoenix Application setup.

### Amazon SES Setup

First you will need to sign in to your amazon account [here](https://console.aws.amazon.com/ses/).

Once you are signed in you should see a nav bar on the left of the screen.
Click on SMTP settings in the nav bar.

<img src="https://cloud.githubusercontent.com/assets/15983736/23793390/d9b88248-0582-11e7-9e89-15d6c84f688c.png" />

From this page make a note of your `Server Name` and `Port`.

Then click <img src="https://cloud.githubusercontent.com/assets/15983736/23793405/eb56697a-0582-11e7-8d27-27d07225250f.png" />

You may then choose a username, or go with the default name. On the
bottom right of the screen click "Create".

Click "Show User SMTP Security Credentials" and make a note of your "SMTP
Username" and "SMTP Password"

Next we need to authorise an email address for testing. Return back to the
[SES dashboard](https://console.aws.amazon.com/ses/).

Click on "Email Addresses" under "Identity Management" on the nav bar on the
left.

<img src="https://cloud.githubusercontent.com/assets/15983736/23793419/fd6c22a8-0582-11e7-9d79-42afd0521133.png" />

Click <img src="https://cloud.githubusercontent.com/assets/15983736/23793429/0c8d2188-0583-11e7-9c1e-8f4f41cee20b.png" /> and type in a real email address which you will use for testing your application

Check your email and click the validation link. If this has not shown up
immediately, double check you input your email correctly. It may take some
time but it is usually immediate.

Great! You are now ready to start building the application.

Before continuing, you should have made a note of the following:

* Server Name
* Port
* SMTP Username
* SMTP Password
* The validated email address

We now have everything we need from AWS and can start building the application.

### Phoenix Application

```bash
$ mix phoenix.new ses_email_test --no-ecto
("y" to Install dependencies)
$ cd ses_email_test
```
Check your server is running with:
```bash
$ mix phoenix.server
```
Then visiting `http://localhost:4000`

We'll need to install some dependencies which we can do by adding to  `mix.exs`.
Ensure to edit your `deps` and `application` functions as follows:

In your `mix.exs` `deps`,  add in `:bamboo`, `:bamboo_smtp` and `:mock`.

```elixir
defp deps do
  [{:phoenix, "~> 1.2.1"},
    ...
   {:bamboo, "~> 0.7"},
   {:bamboo_smtp, "~> 1.2.1"},
   {:mock, "~> 0.2.0", only: :test}]
end
```

In `mix.exs` `application`, add in `:bamboo`

```elixir
  def application do
    [mod: {SesEmailTest, []},
     applications: [:phoenix, :phoenix_pubsub, :phoenix_html, :cowboy, :logger, :gettext, :bamboo]]
  end   
```     

Now let's install our deps by running:
```bash
$ mix deps.get
```

Next we need to create a `Mailer` module for our application to use,
This will be where we reference the functions which `Bamboo` gives us.
Create a `mailer.ex` file inside of `lib/ses_email_test`

`lib/ses_email_test/mailer.ex`

```elixir
defmodule SesEmailTest.Mailer do
  use Bamboo.Mailer, otp_app: :ses_email_test
end
```

Next we need an `Email` module which will be where we will create our own helpers for sending
emails. Create a `email.ex` file inside of `lib`

`lib/email.ex`

```elixir
defmodule SesEmailTest.Email do
  use Bamboo.Phoenix, view: SesEmailTest.EmailView

  def send_test_email(from_email_address, subject, message) do
    new_email()
    |> to("yourvalidatedemail@example.com")
    |> from(from_email_address) # also needs to be a validated email
    |> subject(subject)
    |> text_body(message)
  end
end
```

Now we need to set up our configuration for our Mailer function.
Add this to your `config.exs` file:

`config/config.exs`
```elixir
...
# Configure mailing
config :ses_email_test, SesEmailTest.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.get_env("SES_SERVER"),
  port: System.get_env("SES_PORT"),
  username: System.get_env("SMTP_USERNAME"),
  password: System.get_env("SMTP_PASSWORD"),
  tls: :always, # can be `:always` or `:never`
  ssl: false, # can be `true`
  retries: 1
...
```

Now we need to ensure to source these environment variables.
Set up an `.env` file in the root of your application with the following:

`.env`
```bash
export SMTP_USERNAME=<smtp_username>
export SMTP_PASSWORD=<smtp_password>
export SES_SERVER=<server_name>
export SES_PORT=<ses_port>
```

Then run:

```bash
source .env
```

Now let's add a route to `router.ex` for rendering our form and sending our data.

`web/router.ex`
```elixir
scope "/", SesEmailTest do
  pipe_through :browser

  get "/", PageController, :index
  resources "/email", EmailController, only: [:index, :create]
end
```

Let's set up our email controller

`web/controllers/email_controller.ex`

```elixir
defmodule SesEmailTest.EmailController do
  use SesEmailTest.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end

  def create(conn, %{"email" => %{"email_from" => email_from,
  "subject" => subject, "message" => message}}) do
    SesEmailTest.Email.send_test_email(email_from, subject, message)
    |> SesEmailTest.Mailer.deliver_now()

    conn
    |> put_flash(:info, "Email Sent")
    |> redirect(to: email_path(conn, :index))
  end
end
```

Create the view:

`web/view/email_view.ex`

```elixir
defmodule SesEmailTest.EmailView do
  use SesEmailTest.Web, :view
end
```

Make your template:

`web/templates/email/index.html.eex`

```elixir
<%= form_for @conn, email_path(@conn, :create), [as: :email], fn f -> %>
  <h5>Fill in the fields to send an email</h5>
  <div class="form-group">
    <%= label f, "Email address", class: "control-label" %>
    <%= text_input f, :email_from, placeholder: "email@example.com", class: "form-control" %>
  </div>
  <div class="form-group">
    <%= label f, :subject, class: "control-label" %>
    <%= text_input f, :subject, class: "form-control" %>
  </div>
  <div class="form-group">
    <%= label f, :message, class: "control-label" %>
    <%= text_input f, :message, class: "form-control" %>
  </div>
  <%= submit "Send", class: "btn btn-primary" %>
<% end %>
```

We can check if everything worked by starting our server with
`mix phoenix.server`, then visiting `localhost:4000/email`.

For this example, you must use an email address that has been validated for
sending and receiving email. You can validate more than one email address, or
use the same email for sending and receiving the email. Put in the email
address which you have validated.

### Testing

#### With Mock

Create your test file so we can begin testing.

`test/controllers/email_controller_test.exs`
```elixir
defmodule SesEmailTest.EmailControllerTest do
  use SesEmailTest.ConnCase, async: false

  test "/email :: index", %{conn: conn} do
    conn = get conn, email_path(conn, :index)
    assert html_response(conn, 200) =~ "Fill in the fields to send an email"
  end

  test "/email :: create", %{conn: conn} do
    conn = post conn, email_path(conn, :create,
      %{"email" => %{"email_from" => <your_verified_email>, "subject" => "Here's a subject", "message" => "With a message"}})
    assert redirected_to(conn, 302) =~ "/email"
  end
end
```

We can run our tests with `mix test`.
Great it worked, but it also sent us an email.
As it may get quite annoying to receive emails every time you run your tests,
let's fix that with the mocking library we installed at the beginning.
Ensure to configure your tests to run asynchronously with `async: false` and
adjust the second test as follows.

`test/controllers/email_controller_test.exs`
```elixir
defmodule SesEmailTest.EmailControllerTest do
  use SesEmailTest.ConnCase, async: false

  import Mock

  test "/email :: index", %{conn: conn} do
    conn = get conn, email_path(conn, :index)
    assert html_response(conn, 200) =~ "Fill in the fields to send an email"
  end

  test "/email :: create", %{conn: conn} do
    with_mock SesEmailTest.Mailer, [deliver_now: fn(_) -> nil end] do
      conn = post conn, email_path(conn, :create,
        %{"email" => %{"email_from" => <your_verified_email>, "subject" => "Here's a subject", "message" => "With a message"}})
      assert redirected_to(conn, 302) =~ "/email"
    end
  end
end
```

Now when running the test we checked everything as we did before, but no email
was sent. That's thanks to stubbing out our `deliver_now` function to not do
anything. Note that when using your application locally, emails will still send.


#### With Bamboo.test

- Add to your config/test.exs file the Bamboo test adapter:
```elixir
config :ses_email_test:, SesEmailTest.Mailer,
  adapter: Bamboo.TestAdapter
```

The values in the test config file will overide the default adapter define in your ```config.exs```

- Test the structure format of an email:
```elixir
test "structure email ok" do

  email = Email.send_email("test@email.com", "Welcome", "Hello there")

  assert email.to == "test@email.com"
  assert email.subject == "Welcome"
  assert email.text_body =~ "Hello there"
end
```

- Test the email has been sent
```elixir
test "Send Welcome email" do
  email = Email.send_email("test@email.com", "Welcome", "Hello there")
  SesEmailTest.Mailer.deliver_now(email)
  assert_delivered_email Email.send_email("test@email.com", "Welcome", "Hello there")
end
```

see [Bamboo.Test documentation](https://hexdocs.pm/bamboo/Bamboo.Test.html) for more details.

### Moving out of testing environment

After testing your application, you will probably want more freedom to send
emails to whoever you want without having to verify each email address.
To do so, you will need to increase your SES Sending Limits.

This can be done by opening a case by following the instructions
[here](http://docs.aws.amazon.com/ses/latest/DeveloperGuide/request-production-access.html).

After your case has been approved by Amazon, you will need to update your
SMTP_USERNAME, SMTP_PASSWORD and SES_SERVER. You can get new credentials by
following the [instructions above](https://github.com/dwyl/learn-phoenix-framework/blob/master/sending-emails.md#amazon-ses-setup).
You can ensure you have the correct SES_SERVER at the same time, as it is also
found under SMTP Settings in the Amazon console.

After approval and updating the required sections, you will be able to send
emails to whoever you want.

### Adding Html to an email

If you want to style your emails you need to be able to add html and then use
inline css. To do this simply use `html_body()` instead of `text_body()`. Then
add your html as your argument.

If you've got lots of html to add you may prefer to add a html template. To do
this use `html_body()` but instead of using your html as your argument you want
to provide your file path within `EEx.eval_file()` so it would end up looking
something like this:

```
def send_html_email(to_email_address, subject) do
  new_email()
  # also needs to be a validated email
  |> from("example@dwyl.com")
  |> to(to_email_address)
  |> subject(subject)
  |> html_body(
    EEx.eval_file(
      "<your-file-path>"
    )
  )
end
```

For a full working example of this see: https://github.com/dwyl/auth.

#### Making a responsive email template

It's important to consider how your email styling will look on different devices
and on different applications. Unfortunately there's not a one-size-fits-all
solution for styling email templates everywhere. There are three key approaches
you can take:

1. Use a design/layout that doesn't need altering for different screens
The most simple solution is style things in a way that is naturally flexible
or not impacted by screen resizing. E.g. having a simple layout that does not
need revising on different screen sizes (tables are where things tend to get
tricky on different screens) and using `rem` or `%` rather than `px` as a unit.
This is a template on desktop and mobile that works for both screen sizes without
any special measures:

![desktop-template](https://user-images.githubusercontent.com/16775804/54979593-73a18080-4f9b-11e9-9d4a-7603ede1a880.png)
![mobile-template](https://user-images.githubusercontent.com/16775804/54979639-96cc3000-4f9b-11e9-8a11-6263e29cc85b.png)

To see the code of this template see: https://github.com/dwyl/auth.

2. Implement the responsive styling methods needed for each device so your email
looks good on all kinds of apps:

Given the title of this section, this might seem like the obvious answer someone
might hope for. Unfortunately this implementation is the most complex which is
why the other options have been given as alternatives! The complexity is due to
the fact that certain styling methods such as setting `max-width` and media
queries are not supported by all apps. For example, the Gmail app (which is more
popular than the default mail app on Android) doesn’t support media queries.
Other sources such as Microsoft Outlook and IE also need their own work arounds
with conditional statements such as `<!--[if (gte mso 9)|(IE)]>`. To cover all
of these scenarios (and more) for making your own responsive template follow this
comprehensive tutorial:
https://webdesign.tutsplus.com/tutorials/creating-a-future-proof-responsive-email-without-media-queries--cms-23919

The tutorial follows the '*fluid hybrid*' method, also referred to as the
*spongy method* of email development.

> The fluid part refers to the fact that we use lots of percentages. The hybrid
part is because we also use max-width to restrict some of our elements on larger
screens

3. Use free responsive pre-made templates available from sites such as this one:
https://tedgoas.github.io/Cerberus/

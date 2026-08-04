# Forgotten Password with Phoenix

### Why?

This is a problem that's happened to *everyone* at some point. You've signed up
somewhere, tried to log in again & you can't with the password you *thought*
you used. What was it?!

![think!](https://media.giphy.com/media/uzZh2psw4J3ri/giphy.gif)

This well-known experience makes having functionality for resetting forgotten
passwords an important part of your phoenix application!

### How?

If you've thought of this before you've done any authentication, you can use an
authentication library such as [coherence](https://github.com/smpallen99/coherence).
However, if you have already built your own authentication plug, or have used
an authentication library which doesn't contain a forgotten password module,
you may need to build your own.

You will need to set up sending emails with Amazon SES. You can find
instructions for how to do this [here](sending-emails.md). When setting up the
function to send the reset email, it will look similar to the
`send_reset_email` function found in
[email.ex](/examples/forgotten_password/lib/email.ex).

The complete files you need to add are located in
[the examples folder]("/examples/forgotten_password"). These are located in the
context of a larger project with user creation and authentication already
implemented, so only the relevant files are found there. We will run through what
happens each step of the way here.

We will be focussing on the
[`PasswordController`](/examples/forgotten_password/web/controllers/password_controller.ex)
The first steps are in the`:new` and `:create` actions. Steps 1 & 2 in the
diagram below are completed in the `:new` action, and the rest are in the
`create` action.

![email-entry-flow](https://cloud.githubusercontent.com/assets/1287388/26449376/bf4eaf7e-4149-11e7-8169-1387f57ba938.png)

Here we are storing the `reset_password_token` and `reset_token_sent_at` in the
already existing sql database. This can also be stored in Redis, you can
make use of [Elixir's ETS](https://elixir-lang.org/getting-started/mix-otp/ets.html)
which is really from Erlang(Erlang Term Storage).

The next steps are in the `edit` action. The edit page is only loaded if the
token is valid, and if the token is not expired for the given time period(24
hours in this case).

![editing-password-flow](https://cloud.githubusercontent.com/assets/1287388/26452477/06c849f6-4158-11e7-93e4-9088e0199dbf.png)

After the user enters a new password, the logic done in the edit action to
check if the token is valid and unexpired is repeated in the `:update` action.
If this is still good, the password is checked that it meets the correct
criteria (e.g. length) and is updated for the user.

![congrats](https://media.giphy.com/media/ehhuGD0nByYxO/giphy.gif)

YAY! Your users can now reset their password if they ever forget it! 

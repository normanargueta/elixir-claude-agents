# Capstone - the web app.
#
# Run it:
#     mix run capstone/app.exs
#
# `ElxAgentTutorial.Web.Router` (Module 7) streams every agent step into the
# browser, so viewers see the searches and reasoning, not just the final
# answer.

alias ElxAgentTutorial.{Capstone, Web}

Web.Router.run(Capstone.build_agent(), port: 4000, title: "Research Assistant")

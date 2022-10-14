local _ = require("gettext")

local GazetteMessages = {

}

GazetteMessages.MENU_SYNC = _("Sync")
GazetteMessages.MENU_LIST_PREVIOUS_RESULTS = _("View last sync results")
GazetteMessages.MENU_MANAGE_SUBSCRIPTIONS = _("Manage subscriptions")
GazetteMessages.MENU_SETTINGS = _("Settings")

GazetteMessages.SUBSCRIPTION_ACTION_DIALOG_EDIT = _("Edit")
GazetteMessages.SUBSCRIPTION_ACTION_DIALOG_DELETE = _("Delete")
GazetteMessages.SUBSCRIPTION_ACTION_DIALOG_CLEAR_RESULTS = _("Clear results")

GazetteMessages.VIEW_SUBSCRIPTIONS_LIST = _("Subscriptions")
GazetteMessages.VIEW_RESULTS_LIST = _("Sync Results")
GazetteMessages.VIEW_RESULTS_SUBSCRIPTION_TITLE = _("Sync Results: %1")
GazetteMessages.RESULT_EXPAND_INFO = _("%1: %2 \n%3")
GazetteMessages.RESULT_ALREADY_DOWNLOADED = _("Already downloaded")
GazetteMessages.RESULT_SUCCESS = _("Success")
GazetteMessages.RESULT_ERROR = _("Error")

GazetteMessages.ERROR_FEED_FETCH = _("Error fetching feed.")
GazetteMessages.ERROR_ENTRY_FETCH = _("Error fetching entry.")
GazetteMessages.ERROR_FEED_NOT_SYNCED = _("Feed must be synced before accessing entries")

GazetteMessages.UNTITLED_FEED = _("Untitled feed (%s)")
GazetteMessages.DEFAULT_NAV_TITLE = _("Table of Contents")

GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_FEED_BEGIN = _("Testing feed...")
GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_FETCH_URL = _("Fetching URL...")
GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_ERROR = _("Error! %1")
GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_SUCCESS = _("Success! Got '%1'")
GazetteMessages.CONFIGURE_SUBSCRIPTION_FEED_NOT_TESTED = _("Feed must be tested and pass before being saved.")

GazetteMessages.SYNC_SUBSCRIPTIONS_SYNC =  _("Syncing subscriptions...")


return GazetteMessages

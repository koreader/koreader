local _ = require("gettext")
local T = require("ffi/util").template

local version = "0.3"

return {
    help = T(_([[
# Gemini client for KOReader
This is a plugin for browsing Gemini in KOReader.

# Quickstart
* Enter the client by selecting "Browse Gemini" from the menu.
* Tap on links to follow them.
* Swipe up to access a navigation menu, or down to go back.

# About Gemini
Gemini is a lightweight text-first alternative to the WWW. It consists of a protocol for fetching gemini:// URLs analogous to https, and the "gemtext" hypertext format analogous to html. Thanks to its simplicity, even the low-end devices which KOReader targets are fully capable of accessing Gemini.
=> gemini://geminiprotocol.net Project Gemini home

# Usage
* Navigate a Gemini document using the usual KOReader UI.
* Tap on a link to follow it.
* Swipe up, or select Browse Gemini again, to access the nav menu (see below) at the current URL.
* Long-press or double-tap on a link to access the nav menu at the link URL.
* Swipe down to go back in history.

Further gestures can be configured through the gesture manager; Gemini events are at the end of the Reader section.

## Nav menu
Buttons perform actions on the displayed URL, which can be edited.
* Identity: Set/change the identity being used at the URL (see below).
* Page Info: Show certificate and other information on the current URL.
* Back: Go back one page in history.
* Unback: Go forwards one page in history; enabled after going back.
* Next: Go to next page in the queue (see below).
* Bookmarks: Show bookmarks page.
* Up: Modify URL by deleting the last component of the path.
* Save: Saves page to filesystem.
* Add: Append URL to the queue (see below).
* Mark: Append URL to bookmarks page.
* Go: Go to URL, reloading if it's the current URL.

### Advanced actions
The cog icon in the nav title bar toggles to the following advanced button actions, which can also be accessed by long-pressing on the button without using the cog icon.

* Edit Identity URLs: Edit which identities are used at which URLs
* View as text: Show source text of current page.
* History: Show full history and unhistory list.
* Edit Queue: Show queue, with option to remove all items.
* Edit Marks: Bring up text editor to edit the bookmarks gemtext page.
* Root: Remove path from URL.
* Prepend: Put URL at front of queue.
* Quick Mark: Add to bookmarks without asking for a description.
* Input: Prompt for input, as if asked by the server.

## Troubleshooting
* If loading pages is slow, consider disabling the "Reading statistics" plugin.
* If an inappropriate action happens when you page forward beyond the end of a file, consider changing the action in Settings -> Document -> End of document action.

## Identities
When connecting to a Gemini URL, you may optionally identify yourself to the server with a cryptographic identity (technically, a TLS client certificate). You can create identities via the Identity button, or import them from another client by placing the .crt and .key files in gemini/identities/ under the koreader data directory.

Once you set an identity to be used at a URL, it will also be used at all subpaths. In particular, if you set an identity to be used at the root of a capsule (gemini://example.net/), it will be used on the whole of the capsule.

Identities are identified within the client by a "petname", which is also the filename they are stored under. This petname is not transmitted to servers you connect to. Some servers expect to see a username when you identify to them (the "Common Name" of the client certificate); this can optionally be set when creating an identity.

## The queue, and offline use
The queue is a list of URLs, intended to facilitate browsing and offline use. The Next button opens the next URL in the queue and deletes it from the queue. Long-pressing a link and selecting Add will append the link to the queue. You can also hold-drag to add multiple links at once through the text selection menu.

By default, if you have a network connection when you add a link to the queue, it will be fetched immediately. A fetched document is stored as temporary file, and can be accessed offline. Unfetched queue items can be fetched in the queue menu, accessible by long-pressing Next. Recent history and unhistory items are also kept as fetched documents. These features can be used to minimise the need to be online.

## Certificate trust
Gemini uses the same cryptography as HTTPS to secure connections, but with a simpler Trust-On-First-Use (TOFU) approach to verifying server identities. This is mostly invisible, but occasionally you will be asked to intervene, and you may then wish to read more about it:
=> about:tofu Further information on TOFU in Gemini and this client

## Scheme proxies
By setting proxies, you can use this client to browse gopher, http(s), and other protocols. Once a proxy server for a protocol scheme is set, navigating to a corresponding URL will make a gemini request to that server for that URL.
=> https://tildegit.org/solderpunk/agena Agena: proxy server software for gopher
=> https://github.com/LukeEmmet/duckling-proxy Duckling-proxy: proxy server software for http(s)
=> https://levior.gitlab.io/ levior: proxy server software for http(s)

# About this client
gemini.koplugin was written and is maintained by Martin Bays <mbays@sdf.org>, and is distributed under the terms of the GPLv3 or later.
This is version %1.
=> gemini://gemini.thegonz.net/gemini.koplugin/ Client home page
]]), version),
    version = version,
    tofu = _([[
# TOFU
In place of the complex Certificate Authority based method used on the WWW, Gemini uses a Trust-On-First-Use (TOFU) approach to verifying server identities (which some users may know from SSH).

When you first connect to a server, the cryptographic server identity it presents (technically, the hashed public key of the tail certificate) is stored and considered trusted. As long as the same server identity is presented on subsequent connections to that host, it must indeed be the server you first connected to. If another server identity is ever presented, you will have to choose how to proceed. There are a few things it could mean:
* The server operator changed their server identity. With a well-configured server, this should almost never happen -- essentially only if advances in technology/mathematics have rendered the underlying cryptography no longer secure. In practice however, some server operators use short-lived certificates which have to be changed once they expire, or are about to, and they (unnecessarily) change their server identity along with the certificate. You will be shown the expiry date to help you decide if this is likely to be what's happening.
* Someone is pretending to be that server (a "meddler-in-the-middle attack"). If this is the case and you proceed with the connection, the attacker will be able to see everything the server usually could -- your requests, including any text input, and which identities you use -- and can interfere with the responses.
* Someone *was* pretending to be that server when you first trusted the server identity, but now the attack has ended. To help you gauge the likelihood of this, you are shown the number of times you have seen the trusted server identity on previous connections.

You will also be shown a SHA256 digest of the certificate the server is now presenting, in case you have some out-of-band way of verifying that this is correct.

You will be given the option to permanently trust the new server identity (forgetting the old one), or to temporarily accept the new server identity for this connection (and for further connections to this host within the next hour), or to cancel the connection.
]]),
    welcome = _([[
# Gemini client: First steps
Welcome. To start using this plugin, please follow these two steps:
* Swipe up, or select "Browse Gemini" from the menus, to bring up the navigation dialog.
* Select Bookmarks; further help and starting points for exploration are available from there.
]]),
    xyzzy = "Nothing happens.",
    blank = "",
    default_bookmarks = _([[
# Starting points
=> about:help Help on using this client

=> gemini://kennedy.gemi.dev/search? Kennedy: Search engine
=> gemini://warmedal.se/~antenna/ Antenna: Gemlog aggregator
=> gemini://cdg.thegonz.net/ CDG: Capsule directory
=> gemini://bbs.geminispace.org/ BBS: Forum
=> gemini://geminiprotocol.net/ Gemini protocol home capsule

# User bookmarks
Add entries here with the "Mark" button. Edit this file by long-pressing the "Bookmarks" button.
]]),
}

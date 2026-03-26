import type { ChannelStream } from "../../types/sports/sportsTypes";

// tv channels
export const channelStreams : ChannelStream[] = [
    {
        baseUrl: "https://rippleplays.shop/newhub/stream-", //https://rippleplays.shop/newhub/stream-1.php
        extension: ".php",
        defaultChannel: "1",
        title: "Ripple Plays",
        provider: "rippleplays",
    },
    {
        baseUrl: "https://shd247.xyz/source", //https://shd247.xyz/source020.html
        extension: ".html",
        defaultChannel: "020",
        title: "Stream HD 24/7",
        provider: "shd247",
    },
    {
        baseUrl: "https://streams.center/embed/ch",
        defaultChannel: "50",
        extension: ".php",
        title: "Streams Center",
        provider: "streamscenter",
    },
    {
        baseUrl: "https://prostreams.shop/now/stream-",
        defaultChannel: "3",
        extension: ".php",
        title: "Pro Streams",
        provider: "prostreams"
    }
]


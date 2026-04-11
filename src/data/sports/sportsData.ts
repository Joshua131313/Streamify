import type { ChannelStream, SportStream } from "../../types/sports/sportsTypes";

export const getSlug = (name: string) => name.split(" ").slice(-1)[0];

// https://embedhd.org/ make a request here and get the schedule, can then get the stream link
// https://embedhd.org/source/fetch.php?hd=622
// https://streamed.site/set.php?622
// <iframe src="https://viewembed.ru/channel/scfw_sandiegopadres" width="100%" height="600" frameborder="0" allowfullscreen></iframe>
// <iframe src="https://viewembed.ru/channel/scfw_coloradorockies" width="100%" height="600" frameborder="0" allowfullscreen></iframe>
// https://viewembed.ru/index.php // very easy to integrate


export const createViewEmbedStreams = (teamsMap: Record<string, any>) : SportStream[] => {
    return [
        {
            provider: "viewembed-home",
            buildStreamUrl: ({ homeTeamAbbrev }) => {
                const home = teamsMap[homeTeamAbbrev as keyof typeof teamsMap];
                const homeNameFormattedForStream = home.id.split("-").join("");
                return `https://viewembed.ru/channel/scfw_${homeNameFormattedForStream}`
            },
            label: "Home"
        },
        {
            provider: "viewembed-away",
            buildStreamUrl: ({ awayTeamAbbrev }) => {
                const away = teamsMap[awayTeamAbbrev as keyof typeof teamsMap];
                const awayNameFormattedForStream = away.id.split("-").join("");
                return `https://viewembed.ru/channel/scfw_${awayNameFormattedForStream}`
            },
            label: "Away",
        },
    ]
}
// tv channels
export const channelStreams: ChannelStream[] = [
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


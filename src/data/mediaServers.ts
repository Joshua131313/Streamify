// Public movie/TV embed templates used by streamex.hn (checked 2026-10-12).
// Availability varies by title; a loaded iframe does not guarantee video playback.
export const mediaServers = [
    { id: "streamex", label: "StreamEx", movie: "https://play.xpass.top/e/movie/{id}", tv: "https://play.xpass.top/e/tv/{id}/{season}/{episode}" },
    { id: "vidy", label: "Vidy", movie: "https://vidy.st/movie/{id}?color=FFFF", tv: "https://vidy.st/tv/{id}/{season}/{episode}?color=FFFF" },
    { id: "bingr", label: "Bingr", movie: "https://bingr.one/watch/movie/{id}", tv: "https://bingr.one/watch/tv/{id}/{season}/{episode}" },
    { id: "core", label: "Core", movie: "https://vidcore.net/movie/{id}", tv: "https://vidcore.net/tv/{id}/{season}/{episode}" },
    { id: "zoryva", label: "Zoryva", movie: "https://zoryva.me/embed/movie/{id}?color=%235865f2&exit=hide&cast=hide", tv: "https://zoryva.me/embed/tv/{id}/{season}/{episode}?color=%235865f2&exit=hide&cast=hide" },
    { id: "cinemaos", label: "CinemaOS", movie: "https://cinemaos.tech/player/{id}", tv: "https://cinemaos.tech/player/{id}/{season}/{episode}" },
    { id: "peach", label: "Peach", movie: "https://peachify.top/embed/movie/{id}", tv: "https://peachify.top/embed/tv/{id}/{season}/{episode}" },
    { id: "mapi", label: "Mapi", movie: "https://vidzen.fun/movie/{id}", tv: "https://vidzen.fun/tv/{id}/{season}/{episode}" },
    { id: "vidsrc", label: "VidSrc", movie: "https://vsembed.ru/embed/movie/{id}", tv: "https://vsembed.ru/embed/tv/{id}/{season}/{episode}" },
    { id: "stellar", label: "Stellar", movie: "https://stellar.rip/en/watch/embed/movie/{id}", tv: "https://stellar.rip/en/watch/embed/tv/{id}-{season}-{episode}" },
    { id: "framex", label: "FrameX", movie: "https://framextv.tech/embed/movie/{id}?autoplay=1", tv: "https://framextv.tech/embed/tv/{id}/{season}/{episode}?autoplay=1" },
    { id: "zxcstream", label: "ZXCStream", movie: "https://www.zxcstream.xyz/player/movie/{id}", tv: "https://www.zxcstream.xyz/player/tv/{id}/{season}/{episode}" },
    { id: "french", label: "French", movie: "https://frembed.buzz/api/film.php?id={id}", tv: "https://frembed.buzz/api/serie.php?id={id}&sa={season}&epi={episode}" },
    { id: "spanish", label: "Spanish", movie: "https://play.modocine.com/play.php/embed/movie/{id}", tv: "https://play.modocine.com/play.php/embed/tv/{id}/{season}/{episode}" },
    { id: "italian", label: "Italian", movie: "https://vixsrc.to/movie/{id}?lang=it", tv: "https://vixsrc.to/tv/{id}/{season}/{episode}?lang=it" },
] as const;

export function getMediaServer(id: string | null) {
    return mediaServers.find(server => server.id === id) ?? mediaServers[0];
}

export function buildMediaEmbedUrl(serverId: string | null, mediaType: "movie" | "tv", id: number, season = 1, episode = 1) {
    const positiveInteger = (value: number) => Number.isInteger(value) && value > 0 ? value : 1;
    return getMediaServer(serverId)[mediaType]
        .replace("{id}", encodeURIComponent(String(id)))
        .replace("{season}", String(positiveInteger(season)))
        .replace("{episode}", String(positiveInteger(episode)));
}

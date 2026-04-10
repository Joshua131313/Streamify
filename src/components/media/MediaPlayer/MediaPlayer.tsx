import { useSearchParams } from "react-router-dom";
import { useEffect, useRef } from "react";
import "./MediaPlayer.css";

import { YouAreWatching } from "./YouAreWatching";
import { useMediaLayoutContext } from "../../layout/MediaLayout/MediaLayoutContext";
import { AppPlayer } from "../../ui/AppPlayer/AppPlayer";
import { EpisodeSelector } from "./EpisodeSelector";
import { useWatchHistoryContext } from "../../../context/WatchHistoryContext";

export const MediaPlayer = ({ modal = true }: { modal?: boolean }) => {
    const [searchParams, setSearchParams] = useSearchParams();
    const { media, mediaType } = useMediaLayoutContext();
    const { saveHistory, removeHistory } = useWatchHistoryContext();

    const prevRef = useRef<{
        season: string | null;
        episode: string | null;
        play: boolean;
    }>({
        season: null,
        episode: null,
        play: false,
    });

    const cancelPlay = () => {
        const newParams = new URLSearchParams(searchParams);
        newParams.delete("play");
        newParams.delete("season");
        newParams.delete("episode");
        setSearchParams(newParams, { replace: true });
    };
//  old vidsrc-embed.ru
// vidsrc.xyz/ https://vidsrc.xyz/embed/movie?tmdb=1429&autoplay=1
// https://vidsrc.xyz/embed/tv?tmdb=1429&season=1&episode=2&autonext=1&autoplay=1
// https://vidsrc.mov/embed/tv/1429/1/1
// vidsrc.icu

    const getMediaSrc = () => {
        if (mediaType === "tv") {
            const season = searchParams.get("season");
            const episode = searchParams.get("episode");
            // return `https://vidsrc.xyz/embed/tv?tmdb=${media.id}&season=${season}&episode=${episode}&autonext=1&autoplay=1`
            return `https://vidsrc.mov/embed/tv/${media.id}/${season}/${episode}?autoplay=1&episodeselector=true&color-D81F26`;
        }
        // return `https://vidsrc.xyz/embed/movie?tmdb=${media.id}&autoplay=1`
        return `https://vidsrc.mov/embed/movie/${media.id}?autoplay=1&color-D81F26`;
    };

    useEffect(() => {
        const season = searchParams.get("season");
        const episode = searchParams.get("episode");
        const hasPlay = searchParams.has("play");

        if (mediaType === "movie") {
            if (hasPlay && !prevRef.current.play) {
                prevRef.current.play = true;

                saveHistory({
                    mediaType: "movie",
                    mediaId: media.id,
                });
            }

            return;
        }

        if (
            season === prevRef.current.season &&
            episode === prevRef.current.episode
        ) {
            return;
        }

        prevRef.current = {
            season,
            episode,
            play: hasPlay,
        };

        if (season && episode) {
            saveHistory({
                mediaType: "tv",
                mediaId: media.id,
                season,
                episode,
            });
        }
    }, [searchParams, media.id, mediaType, saveHistory]);

    useEffect(() => {
        const handleMessage = (event: MessageEvent) => {
            let data: any;

            try {
                data =
                    typeof event.data === "string"
                        ? JSON.parse(event.data)
                        : event.data;
            } catch {
                return;
            }

            const payload = data?.data;
            const type = payload?.event;

            if (!payload) return;

            if (type === "play") {
                document.body.classList.remove("paused");
            }

            if (type === "pause") {
                document.body.classList.add("paused");
            }

            if (type === "ended") {
                removeHistory(
                    media.id,
                    mediaType === "tv" ? "tv" : "movie"
                );
            }
        };

        window.addEventListener("message", handleMessage);
        return () => window.removeEventListener("message", handleMessage);
    }, [media.id, mediaType, removeHistory]);

    return (
        <AppPlayer
            cancelPlay={cancelPlay}
            modal={modal}
            src={getMediaSrc()} 
        >
            <YouAreWatching />
            {mediaType === "tv" && <EpisodeSelector />}
        </AppPlayer>
    );
};
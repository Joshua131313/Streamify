import { useSearchParams } from "react-router-dom";
import { useEffect, useRef, useState } from "react";
import "./MediaPlayer.css";

import { YouAreWatching } from "./YouAreWatching";
import { useMediaLayoutContext } from "../../layout/MediaLayout/MediaLayoutContext";
import { AppPlayer } from "../../ui/AppPlayer/AppPlayer";
import { EpisodeSelector } from "./EpisodeSelector";
import { useWatchHistoryContext } from "../../../context/WatchHistoryContext";
import { Button } from "../../ui/Button/Button";
import type { MediaStreamProviders } from "../../../types";


export const MediaPlayer = ({ modal = true }: { modal?: boolean }) => {
    const [searchParams, setSearchParams] = useSearchParams();
    const { media, mediaType } = useMediaLayoutContext();
    const { saveHistory, removeHistory } = useWatchHistoryContext();
    const [streamProvider, setStreamProvider] = useState<MediaStreamProviders>("vidking");

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
        const season = searchParams.get("season");
        const episode = searchParams.get("episode");

        const providers = {
            vidking: {
                movie: `https://www.vidking.net/embed/movie/${media.id}?color=e50914&autoPlay=true`,
                tv: `https://www.vidking.net/embed/tv/${media.id}/${season}/${episode}?color=e50914&autoPlay=true&nextEpisode=true`
            },
            vidsrc: {
                movie: `https://vidsrcme.ru/embed/movie/${media.id}`,
                tv: `https://vidsrcme.ru/embed/tv/${media.id}/${season}/${episode}`
            }
        };

        const provider = providers[streamProvider as keyof typeof providers];

        if (!provider) return "";

        return mediaType === "tv" ? provider.tv : provider.movie;
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
            className={streamProvider}
        >
            <YouAreWatching />
            {mediaType === "tv" && <EpisodeSelector />}
            <div className={`stream-provider-buttons ${streamProvider}`}>
                <Button className="secondary" onClick={() => setStreamProvider("vidking")}>
                    Vidking
                </Button>
                <Button className="secondary" onClick={() => setStreamProvider("vidsrc")}>
                    Vidsrc
                </Button>
            </div>
        </AppPlayer>
    );
};
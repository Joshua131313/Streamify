import { useSearchParams } from "react-router-dom";
import { useEffect, useRef, useState, useCallback } from "react";
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

    const [streamProvider, setStreamProvider] =
        useState<MediaStreamProviders>("vidking");

    const hasInitializedRef = useRef(false);

    const lastEpisodeRef = useRef<string | null>(null);

    const cancelPlay = () => {
        const newParams = new URLSearchParams(searchParams);
        updateHistory();
        newParams.delete("play");
        newParams.delete("season");
        newParams.delete("episode");
        setSearchParams(newParams, { replace: true });
    };

    const getMediaSrc = () => {
        const season = Number(searchParams.get("season")) || 1;
        const episode = Number(searchParams.get("episode")) || 1;

        const providers = {
            vidking: {
                movie: `https://www.vidking.net/embed/movie/${media.id}?color=e50914&autoPlay=true`,
                tv: `https://www.vidking.net/embed/tv/${media.id}/${season}/${episode}?color=e50914&autoPlay=true&nextEpisode=true`,
            },
            vidsrc: {
                movie: `https://vidsrcme.ru/embed/movie/${media.id}`,
                tv: `https://vidsrcme.ru/embed/tv/${media.id}/${season}/${episode}`,
            },
        };

        const provider = providers[streamProvider];
        return mediaType === "tv" ? provider.tv : provider.movie;
    };

    const updateHistory = useCallback(() => {
        const seasonParam = searchParams.get("season");
        const episodeParam = searchParams.get("episode");

        if (mediaType === "movie") {
            saveHistory({
                mediaType: "movie",
                mediaId: media.id,
            });
            return;
        }

        const payload: {
            mediaType: "tv";
            mediaId: number;
            season?: number;
            episode?: number;
        } = {
            mediaType: "tv",
            mediaId: media.id,
        };

        if (seasonParam) {
            payload.season = Number(seasonParam);
        }

        if (episodeParam) {
            payload.episode = Number(episodeParam);
        }

        saveHistory(payload);
    }, [media.id, mediaType, searchParams, saveHistory]);

    useEffect(() => {
        const hasPlay = searchParams.has("play");
        if (!hasPlay) return;

        if (!hasInitializedRef.current) {
            hasInitializedRef.current = true;
            updateHistory();
        }
    }, [searchParams, updateHistory]);

    useEffect(() => {
        if (mediaType !== "tv") return;

        const season = searchParams.get("season");
        const episode = searchParams.get("episode");

        const key = `${season}-${episode}`;

        if (!season || !episode) return;

        if (lastEpisodeRef.current !== key) {
            lastEpisodeRef.current = key;
            updateHistory();
        }
    }, [searchParams, mediaType, updateHistory]);

    useEffect(() => {
        return () => {
            updateHistory();
        };
    }, []);

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

                updateHistory();
            }

            if (type === "pause") {
                document.body.classList.add("paused");

                updateHistory();
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
    }, [media.id, mediaType, updateHistory, removeHistory]);

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
                <Button
                    className="secondary"
                    onClick={() => setStreamProvider("vidking")}
                >
                    Server 1
                </Button>

                <Button
                    className="secondary"
                    onClick={() => setStreamProvider("vidsrc")}
                >
                    Server 2
                </Button>
            </div>
        </AppPlayer>
    );
};
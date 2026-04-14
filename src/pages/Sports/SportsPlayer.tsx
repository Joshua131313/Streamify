import { useNavigate, useSearchParams } from "react-router-dom";
import {
    formatChannel,
    getSportStream,
    getStreamURL
} from "../../utils/sports/sportsUtils";
import { AppPlayer } from "../../components/ui/AppPlayer/AppPlayer";
import type { Leagues, TeamAbbrevs, TStreamProvider } from "../../types/sports/sportsTypes";
import { Icon } from "../../components/ui/Icon/Icon";
import { FaChevronDown, FaChevronUp } from "react-icons/fa";
import { Input } from "../../components/ui/Input/Input";
import { useState, useEffect, useRef } from "react";
import { Button } from "../../components/ui/Button/Button";
import { SEO } from "../../components/SEO";

export const SportsPlayer = () => {
    const navigate = useNavigate();
    const [searchParams, setSearchParams] = useSearchParams();
    const provider = searchParams.get("provider");
    const channel = searchParams.get("channel");
    const league = searchParams.get("league") as Leagues | null;
    const awayTeamAbbrev = searchParams.get("away") as TeamAbbrevs;
    const homeTeamAbbrev = searchParams.get("home") as TeamAbbrevs;

    const isTV = searchParams.get("tv") === "1";

    const allStreams = league ? getSportStream(league) : [];

    const [inputValue, setInputValue] = useState(channel || "");
    const channelAsNumber = Number(channel);
    const decrementChannelButtonEnabled = channelAsNumber > 1;

    useEffect(() => {
        if (channel !== inputValue) {
            setInputValue(channel || "");
        }
    }, [channel]);

    const updateChannel = (newChannel: string) => {
        if (!newChannel || isNaN(Number(newChannel))) return;

        const formatted = formatChannel(newChannel, provider!);

        if (formatted === channel) return;

        const newParams = new URLSearchParams(searchParams);
        newParams.set("channel", formatted);
        setSearchParams(newParams);
    };

    const incrementChannel = () => {
        updateChannel(String(channelAsNumber + 1));
    };

    const decrementChannel = () => {
        if (decrementChannelButtonEnabled) {
            updateChannel(String(channelAsNumber - 1));
        }
    };

    const switchProvider = (newProvider: TStreamProvider) => {
        const newParams = new URLSearchParams(searchParams);
        newParams.set("provider", newProvider);
        setSearchParams(newParams);
    };

    const cancelWatch = () => {
        navigate(-1);
    };

    let src: string | null = null;

    if (isTV) {
        if (provider && channel) {
            src = getStreamURL(provider as TStreamProvider, channel);
        }
    } else {
        if (provider && league) {
            const stream = allStreams.find(s => s.provider === provider);

            if (stream) {
                src = stream.buildStreamUrl({ awayTeamAbbrev, homeTeamAbbrev });
            }
        }
    }

    if (!src) return null;

    return (
        <>
            {allStreams.length > 0 && (
                <div className="alt-streams">
                    {allStreams.map((stream, i) => (
                        <Button
                            className={provider === stream.provider ? "active-provider" : ""}
                            key={stream.provider}
                            onClick={() => switchProvider(stream.provider)}
                        >
                            {stream.label ?? `Stream ${i + 1}`}
                        </Button>
                    ))}
                </div>
            )}
            <SEO
                title={`${awayTeamAbbrev} @ ${homeTeamAbbrev}`}
                description="Watch live sports streams on Streamify"
            />
            <AppPlayer
                cancelPlay={cancelWatch}
                src={src}
            />

            {isTV && (
                <div className="stream-controls">
                    <Icon Icon={FaChevronUp} onClick={incrementChannel} />

                    <Input
                        value={inputValue}
                        onChange={(e) => {
                            const val = e.target.value;
                            if (/^\d*$/.test(val)) {
                                setInputValue(val);
                            }
                        }}
                        onBlur={() => updateChannel(inputValue)}
                        onKeyDown={(e) => {
                            if (e.key === "Enter") {
                                updateChannel(inputValue);
                            }
                        }}
                    />

                    <Icon Icon={FaChevronDown} onClick={decrementChannel} />
                </div>
            )}
        </>
    );
};
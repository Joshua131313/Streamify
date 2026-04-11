import { useSearchParams } from "react-router-dom";
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
import { useState, useEffect } from "react";
import { Button } from "../../components/ui/Button/Button";

export const SportsPlayer = () => {
    const [searchParams, setSearchParams] = useSearchParams();
    // 🔹 Params
    const provider = searchParams.get("provider");
    const channel = searchParams.get("channel");
    const league = searchParams.get("league") as Leagues | null;
    const awayTeamAbbrev = searchParams.get("away") as TeamAbbrevs;
    const homeTeamAbbrev = searchParams.get("home") as TeamAbbrevs;

    const isTV = searchParams.get("tv") === "1";

    // 🔹 Streams
    const allStreams = league ? getSportStream(league) : [];

    // 🔹 TV input state
    const [inputValue, setInputValue] = useState(channel || "");
    const channelAsNumber = Number(channel);
    const decrementChannelButtonEnabled = channelAsNumber > 1;

    useEffect(() => {
        if (channel !== inputValue) {
            setInputValue(channel || "");
        }
    }, [channel]);

    // 🔥 Channel update
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

    // 🔁 Provider switch
    const switchProvider = (newProvider: TStreamProvider) => {
        const newParams = new URLSearchParams(searchParams);
        newParams.set("provider", newProvider);
        setSearchParams(newParams);
    };

    // ❌ Cancel player
    const cancelWatch = () => {
        const newParams = new URLSearchParams(searchParams);
        newParams.delete("provider");
        newParams.delete("channel");
        newParams.delete("league");
        newParams.delete("away");
        newParams.delete("home");
        newParams.delete("tv");
        setSearchParams(newParams, { replace: true });
    };

    // 🔥 SIMPLE SOURCE LOGIC (original style)
    let src: string | null = null;

    if (isTV) {
        if (provider && channel) {
            src = getStreamURL(provider as TStreamProvider, channel);
        }
    } else {
        if (provider && league) {
            const stream = allStreams.find(s => s.provider === provider);

            if (stream) {
                src = stream.buildStreamUrl({awayTeamAbbrev, homeTeamAbbrev});
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
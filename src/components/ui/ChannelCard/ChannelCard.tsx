import { FaPlay } from "react-icons/fa";
import type { SportStream } from "../../../types/sports/sportsTypes"
import { Button } from "../Button/Button";
import { Input } from "../Input/Input";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { WatchButton } from "../Button/WatchButton";
import "./ChannelCard.css"
import { formatChannel } from "../../../utils/sports/sportsUtils";

interface Props {
    stream: SportStream;
}

export const ChannelCard = (props: Props) => {
    const { stream } = props;
    const [channel, setChannel] = useState<number>(Number(stream.defaultChannel));

    return (
        <div className="channel-card">
            <strong>{stream.title}</strong>
            <div className="channel-controls">
                <Input 
                    placeholder={`Channel: ${stream.defaultChannel}`} 
                    value={channel}
                    onChange={(e) => setChannel(Number(e.target.value))}
                />
                <WatchButton 
                    channel={formatChannel(String(channel) || "", stream.provider!)}
                    streamProvider={stream.provider}
                    additionalParams="&tv=1"
                    variant="button"
                />
            </div>
        </div>
    )
}
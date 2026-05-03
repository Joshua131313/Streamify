import { useEffect, useState } from "react";
import { useLiveChat } from "../../../hooks/sportsHooks/useLiveChat";
import { Button } from "../../ui/Button/Button";
import { Input } from "../../ui/Input/Input";
import "./LiveChat.css"
import { Icon } from "../../ui/Icon/Icon";
import { FaMessage } from "react-icons/fa6";
import { FaChevronLeft, FaChevronRight, FaCog, FaPaperPlane, FaReply, FaShare, FaShareAlt } from "react-icons/fa";
import { getColorFromUsername } from "../../../utils/helpers";
import { Textarea } from "../../ui/Textarea/Textarea";
import { BsPaperclip, BsSendFill } from "react-icons/bs";

interface Props {
    gameId: string;
}

export const LiveChat = (props: Props) => {
    const { gameId } = props;
    const { messages, sendMessage } = useLiveChat({ gameId });
    const [message, setMessage] = useState("");
    const [showChat, setShowChat] = useState(true);

    const messagesRender = messages.map(message => {
        const color = getColorFromUsername(message.senderName);
        return (
            <div className="message">
                <span style={{ color: color }}>{message.senderName}</span>
                <span>: {message.message}</span>
                <Icon Icon={FaReply} className="reply-icon" />
                {/* <p>Send time: {message.sentAt?.toDate().toLocaleTimeString()}</p> */}
            </div>
        )
    })

    useEffect(() => {
        if (showChat) {
            document.body.classList.add("sports-live-chat-expanded");
        }
        else {
            document.body.classList.remove("sports-live-chat-expanded");
        }
        return () => {
            document.body.classList.remove("sports-live-chat-expanded");
        }
    }, [showChat])

    return (
        <>
            {
                showChat &&
                <form className="live-chat" onSubmit={(e) => {
                    e.preventDefault();
                    sendMessage(message);
                    setMessage("")
                }}>
                    <div className="live-chat-header">
                        <div>
                            <div className="live-indicator" />
                            <span>{gameId}</span>
                        </div>
                        <div>
                            <Icon
                                Icon={FaShareAlt}
                                onClick={() => {
                                    if (navigator.share) {
                                        navigator.share({
                                            title: document.title,
                                            text: "Join the game",
                                            url: window.location.href,
                                        }).catch(() => { });
                                    }
                                }}
                            />
                            <Icon Icon={FaCog} />
                        </div>
                    </div>
                    <div className="live-chat-messages">
                        <p className="welcome-message">Welcome to the live chat</p>
                        {messagesRender}
                    </div>
                    <div className="live-chat-toolbar">
                        <Textarea
                            placeholder="Send a message..."
                            value={message}
                            onChange={(e) => setMessage(e.target.value)}
                        />
                        <button className={message ? "valid" : ""}><BsSendFill /></button>
                    </div>
                </form>
            }
            <div onClick={() => setShowChat(!showChat)} className={`sidebar-toggler live-chat-sidebar-toggler ${showChat ? "active" : ""}`}>
                {
                    showChat ? <FaChevronRight /> : <FaChevronLeft />
                }
            </div>
        </>
    )
}
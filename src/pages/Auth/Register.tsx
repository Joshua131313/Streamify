import { useState } from "react"
import { Button } from "../../components/ui/Button/Button"
import { Input } from "../../components/ui/Input/Input"
import { Auth } from "./Auth"
import { useAuthProvider } from "../../context/AuthContext"
import { useNavigate } from "react-router-dom"


export const Register = () => {
    const { register } = useAuthProvider();
    const [firstName, setFirstName] = useState("");
    const [firstNameError, setFirstNameError] = useState("");
    const [lastName, setLastName] = useState("");
    const [lastNameError, setLastNameError] = useState("");
    const [email, setEmail] = useState("");
    const [emailError, setEmailError] = useState("");
    const [passwordError, setPasswordError] = useState("")
    const [password, setPassword] = useState("");
    const navigate = useNavigate();

  const handleRegister = async () => {
    let hasError = false;

    setFirstNameError("");
    setLastNameError("");
    setEmailError("");
    setPasswordError("");

    if (!firstName) {
        setFirstNameError("First name required");
        hasError = true;
    }

    if (!lastName) {
        setLastNameError("Last name required");
        hasError = true;
    }

    if (!email) {
        setEmailError("Email is required");
        hasError = true;
    }

    if (!password || password.length < 6) {
        setPasswordError("Password must be at least 6 characters");
        hasError = true;
    }

    if (hasError) return;

    try {
        await register(firstName, lastName, email, password);
        navigate("/")
    } catch (err: any) {
        console.log(err.code);

        switch (err.code) {
            case "auth/email-already-in-use":
                setEmailError("Email already in use");
                break;

            case "auth/invalid-email":
                setEmailError("Invalid email");
                break;

            case "auth/weak-password":
                setPasswordError("Password too weak");
                break;

            default:
                setEmailError("Registration failed");
        }
    }
};

    return (
        <Auth
            onSubmit={handleRegister}
            title="Register"
            header={{
                title: "Already have an account?",
                link: {
                    label: "Login",
                    to: "/login"
                }
            }}
            type="register"
            childrenContainerClassName="login"
        >
            <div className="name">
                <Input error={firstNameError} placeholder="First Name" value={firstName} onChange={(e) => {
                    setFirstName(e.target.value);
                    setFirstNameError("")
                }} />
                <Input error={lastNameError} placeholder="Last Name" value={lastName} onChange={(e) => {
                    setLastName(e.target.value)
                    setLastNameError("")
                }} />
            </div>
            <Input error={emailError} placeholder="Email" value={email} onChange={(e) => {
                setEmail(e.target.value);
                setEmailError("");
            }} />
            <Input error={passwordError} placeholder="Password" value={password} onChange={(e) => {
                setPassword(e.target.value);
                setPasswordError("")
            }} />
            <Button>
                Register
            </Button>
        </Auth>
    )
}
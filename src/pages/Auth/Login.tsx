import { Link, useNavigate } from "react-router-dom"
import { Button } from "../../components/ui/Button/Button"
import { Input } from "../../components/ui/Input/Input"
import { Auth } from "./Auth"
import { useAuthProvider } from "../../context/AuthContext"
import { useState } from "react"


export const Login = () => {
    const [email, setEmail] = useState("");
    const [emailError, setEmailError] = useState("");

    const [password, setPassword] = useState("");
    const [passwordError, setPasswordError] = useState("")
    const [loginLoading, setLoginLoading] = useState(false);
    const navigate = useNavigate();

    const { loginWithEmail, loginWithProvider } = useAuthProvider()

    const handleLogin = async () => {
        let hasError = false;
        if(!email) {
            setEmailError("Email is required");
            hasError = true;
        }
        if(!password) {
            setPasswordError("Password is required");
            hasError = true;
        }
        if(hasError) {
            return;
        }
        try {
            setLoginLoading(true)
            await loginWithEmail(email, password);
            // clear errors on success
            navigate("/")
            setEmailError("");
            setPasswordError("");

        } catch (err: any) {
            const code = err.code;
            console.log(err.code)
            console.log(err.message)
            if (code === "auth/user-not-found") {
                setEmailError("No account found with this email");
                setPasswordError("");
            }
            else if (code === "auth/wrong-password") {
                setPasswordError("Incorrect password");
                setEmailError("");
            }
            else if (code === "auth/invalid-email") {
                setEmailError("Invalid email format");
            }
            else {
                setEmailError("Login failed");
                setPasswordError("");
            }
        }
        finally {
            setLoginLoading(false);
        }
    };

    return (
        <Auth
            onSubmit={() => handleLogin()}
            title="Login"
            type="login"
            childrenContainerClassName="login"
            header={{
                title: "Don't have an account?",
                link: {
                    label: "Register",
                    to: "/register"
                }
            }}
        >
            <Input error={emailError} placeholder="Email" value={email} onChange={(e) => {
                setEmail(e.target.value);
                setEmailError("");
            }} />
            <Input error={passwordError} placeholder="Password" value={password} onChange={(e) => {
                setPassword(e.target.value);
                setPasswordError("")
            }} />
            <Link className="forgot-password-link" to={"/forgot-password"}>Forgot password?</Link>
            <Button loading={false}>
                Login
            </Button>
        </Auth>
    )
}
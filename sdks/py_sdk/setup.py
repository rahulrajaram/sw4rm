from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="sw4rm-sdk",
    version="0.6.0",
    author="SW4RM",
    description="Python SDK for the SW4RM Agentic Protocol",
    long_description=long_description,
    long_description_content_type="text/markdown",
    packages=find_packages(),
    python_requires=">=3.7",
    install_requires=requirements,
    extras_require={
        "dev": [
            "grpcio-tools>=1.56,<2",
            "pytest>=7.0",
            "pytest-asyncio",
            "black",
            "flake8",
        ],
        "groq": [
            "groq>=0.4",
        ],
        "anthropic": [
            "anthropic>=0.18",
        ],
        "llm": [
            "groq>=0.4",
            "anthropic>=0.18",
        ],
    },
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Intended Audience :: Developers",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
)

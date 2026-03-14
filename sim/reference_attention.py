import numpy as np


def softmax(values: np.ndarray, axis: int = -1) -> np.ndarray:
    shifted = values - np.max(values, axis=axis, keepdims=True)
    exp_values = np.exp(shifted)
    return exp_values / np.sum(exp_values, axis=axis, keepdims=True)


def attention(query: np.ndarray, key: np.ndarray, value: np.ndarray) -> np.ndarray:
    scale = np.sqrt(query.shape[-1])
    scores = (query @ key.T) / scale
    weights = softmax(scores, axis=-1)
    return weights @ value

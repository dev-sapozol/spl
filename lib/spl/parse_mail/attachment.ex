defmodule Spl.ParseMail.Attachment do
  defstruct [:filename, :content_type, :content, :size, :encoding]

  @type t :: %__MODULE__{
          filename: String.t(),
          content_type: String.t(),
          content: binary(),
          size: non_neg_integer(),
          encoding: String.t()
        }

  @doc "Crea un nuevo attachment"
  @spec new(String.t(), String.t(), binary()) :: t()
  def new(filename, content_type, content) do
    %__MODULE__{
      filename: filename,
      content_type: content_type,
      content: content,
      size: byte_size(content),
      encoding: "base64"
    }
  end

  @doc "Obtiene la extensión del archivo"
  @spec get_extension(t()) :: String.t()
  def get_extension(%__MODULE__{filename: filename}) do
    case String.split(filename, ".") do
      [_] -> ""
      parts -> "." <> List.last(parts)
    end
  end

  @doc "Verifica si es una imagen"
  @spec is_image?(t()) :: boolean()
  def is_image?(%__MODULE__{content_type: content_type}) do
    String.starts_with?(content_type, "image/")
  end

  @doc "Verifica si es un documento"
  @spec is_document?(t()) :: boolean()
  def is_document?(%__MODULE__{content_type: content_type}) do
    String.starts_with?(content_type, "application/")
  end

  @doc "Obtiene el tamaño formateado en KB/MB"
  @spec format_size(t()) :: String.t()
  def format_size(%__MODULE__{size: size}) do
    cond do
      size < 1024 -> "#{size} B"
      size < 1024 * 1024 -> "#{Float.round(size / 1024, 2)} KB"
      true -> "#{Float.round(size / (1024 * 1024), 2)} MB"
    end
  end
end

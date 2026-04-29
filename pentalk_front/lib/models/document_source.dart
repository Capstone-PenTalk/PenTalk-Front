class DocumentSource {
  final String materialId;
  final String pdfUrl;
  final String localPdfPath;
  final int pageCount;
  final int currentPage;
  final List<DocumentPageSource> pages;

  const DocumentSource({
    required this.materialId,
    required this.pdfUrl,
    required this.localPdfPath,
    required this.pageCount,
    required this.currentPage,
    required this.pages,
  });

  factory DocumentSource.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'] as List<dynamic>? ?? const [];
    return DocumentSource(
      materialId: json['materialId']?.toString() ?? '',
      pdfUrl: json['pdfUrl']?.toString() ?? '',
      localPdfPath: json['localPdfPath']?.toString() ?? '',
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 1,
      pages: rawPages
          .whereType<Map>()
          .map((page) => DocumentPageSource.fromJson(Map<String, dynamic>.from(page)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'materialId': materialId,
      'pdfUrl': pdfUrl,
      'localPdfPath': localPdfPath,
      'pageCount': pageCount,
      'currentPage': currentPage,
      'pages': pages.map((page) => page.toJson()).toList(),
    };
  }

  String pageKeyFor(int pageNumber) => '$materialId:$pageNumber';

  Map<String, int> createPageNumberMap() {
    return {
      for (final page in pages) pageKeyFor(page.pageNumber): page.pageNumber,
    };
  }

  DocumentSource copyWith({
    String? materialId,
    String? pdfUrl,
    String? localPdfPath,
    int? pageCount,
    int? currentPage,
    List<DocumentPageSource>? pages,
  }) {
    return DocumentSource(
      materialId: materialId ?? this.materialId,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      localPdfPath: localPdfPath ?? this.localPdfPath,
      pageCount: pageCount ?? this.pageCount,
      currentPage: currentPage ?? this.currentPage,
      pages: pages ?? this.pages,
    );
  }
}

class DocumentPageSource {
  final int pageNumber;
  final String? imagePath;
  final String? thumbnailPath;
  final double width;
  final double height;

  const DocumentPageSource({
    required this.pageNumber,
    this.imagePath,
    this.thumbnailPath,
    required this.width,
    required this.height,
  });

  factory DocumentPageSource.fromJson(Map<String, dynamic> json) {
    return DocumentPageSource(
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 1,
      imagePath: json['imagePath']?.toString(),
      thumbnailPath: json['thumbnailPath']?.toString(),
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pageNumber': pageNumber,
      if (imagePath != null) 'imagePath': imagePath,
      if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
      'width': width,
      'height': height,
    };
  }

  DocumentPageSource copyWith({
    int? pageNumber,
    String? imagePath,
    String? thumbnailPath,
    double? width,
    double? height,
  }) {
    return DocumentPageSource(
      pageNumber: pageNumber ?? this.pageNumber,
      imagePath: imagePath ?? this.imagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
